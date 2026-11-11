"""Private development worker for CasaReel Walk 3D jobs.

The API accepts only a zip written by the app.  Extraction is path-safe, a job is
processed at a time, and every endpoint requires a bearer token.  Training and
video rendering are external commands so the worker stays independent of a
particular Brush release or renderer.
"""

from __future__ import annotations

import asyncio
import json
import os
import re
import shlex
import shutil
import subprocess
import time
import uuid
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal, Optional

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import FileResponse

from init_points import read_points, write_init_ply

TOKEN = os.environ.get("CASAREEL_WALK3D_TOKEN", "")
DATA_DIR = Path(os.environ.get("WALK3D_DATA_DIR", "/Users/Shared/CasaReelWalk3DJobs")).expanduser()
MAX_CAPTURE_BYTES = 750 * 1024 * 1024
MAX_ARCHIVE_FILES = 300
JOB_LOCK = asyncio.Lock()
JOBS: dict[str, "Job"] = {}


@dataclass
class Job:
    id: str
    directory: Path
    state: Literal["queued", "training", "rendering", "finished", "failed", "cancelled"] = "queued"
    progress: float = 0.0
    message: Optional[str] = None
    video: Optional[Path] = None
    process: Optional[subprocess.Popen] = field(default=None, repr=False)

    def response(self) -> dict:
        # Do not use dataclasses.asdict here: it deep-copies every field before
        # filtering, and Popen contains a non-copyable thread lock while training.
        # The app only needs this safe, JSON-serializable public status.
        return {
            "id": self.id,
            "state": self.state,
            "progress": self.progress,
            "message": self.message,
            "video_ready": self.video is not None and self.video.is_file(),
        }


app = FastAPI(title="CasaReel Walk 3D worker", docs_url=None, redoc_url=None)


def require_token(authorization: Optional[str] = Header(default=None)) -> None:
    if not TOKEN or authorization != f"Bearer {TOKEN}":
        raise HTTPException(status_code=401, detail="unauthorized")


def job_or_404(job_id: str) -> Job:
    job = JOBS.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="job_not_found")
    return job


def safe_extract(archive: Path, destination: Path) -> None:
    with zipfile.ZipFile(archive) as source:
        entries = source.infolist()
        if len(entries) > MAX_ARCHIVE_FILES:
            raise ValueError("too_many_files")
        for entry in entries:
            target = (destination / entry.filename).resolve()
            if not str(target).startswith(f"{destination.resolve()}{os.sep}"):
                raise ValueError("unsafe_archive_path")
            if entry.is_dir() or entry.filename in {"capture.json", "points.bin"} or re.fullmatch(r"frames/frame_\d{5}\.jpg", entry.filename):
                continue
            raise ValueError("unexpected_archive_file")
        source.extractall(destination)


def write_nerfstudio_dataset(capture: Path, dataset: Path) -> None:
    manifest = json.loads((capture / "capture.json").read_text())
    frames = manifest.get("frames")
    if manifest.get("format") != "casareel-walk3d-capture" or not isinstance(frames, list) or not 20 <= len(frames) <= 240:
        raise ValueError("invalid_capture_manifest")
    images = dataset / "images"
    images.mkdir(parents=True)
    output_frames = []
    for frame in frames:
        name = frame.get("image")
        matrix = frame.get("camera_to_world")
        if not isinstance(name, str) or not re.fullmatch(r"frame_\d{5}\.jpg", name) or not isinstance(matrix, list) or len(matrix) != 16:
            raise ValueError("invalid_capture_frame")
        source = capture / "frames" / name
        if not source.is_file():
            raise ValueError("missing_capture_image")
        shutil.copy2(source, images / name)
        # CasaReel stores column-major OpenCV camera-to-world (x right, y down, z forward).
        # Nerfstudio writes row-major OpenGL/ARKit camera-to-world (x right, y up, z back).
        # Right-multiplying the OpenCV pose by diag(1, -1, -1, 1) returns that convention.
        columns = [matrix[index:index + 4] for index in range(0, 16, 4)]
        columns[1] = [-value for value in columns[1]]
        columns[2] = [-value for value in columns[2]]
        transform = [[columns[column][row] for column in range(4)] for row in range(4)]
        output_frames.append({"file_path": f"images/{name}", "transform_matrix": transform})
    first = frames[0]
    transforms = {
        "camera_model": "OPENCV",
        "fl_x": first["fx"], "fl_y": first["fy"], "cx": first["cx"], "cy": first["cy"],
        "w": first["width"], "h": first["height"], "frames": output_frames,
    }
    (dataset / "transforms.json").write_text(json.dumps(transforms, indent=2))
    write_initial_points(capture, dataset)


def write_initial_points(capture: Path, dataset: Path) -> None:
    """ARKit's feature points start the training (Brush picks up `init.ply` in the dataset folder).

    Without them Brush scatters random splats around the cameras and the room collapses into a thin slab
    along the walked path. The points are optional: a broken file only costs quality, never the job.
    """
    try:
        write_init_ply(read_points(capture / "points.bin"), dataset / "init.ply")
    except (OSError, ValueError) as error:
        print(f"Walk 3D capture has no usable ARKit points ({error}); training from random init", flush=True)


def command(template: str, **values: Path) -> list[str]:
    if not template:
        raise RuntimeError("worker_command_not_configured")
    return [part.format(**{key: str(value) for key, value in values.items()}) for part in shlex.split(template)]


async def run_command(job: Job, args: list[str]) -> None:
    job.process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    process = job.process
    output = await asyncio.to_thread(process.communicate)
    return_code = process.returncode
    job.process = None
    if job.state == "cancelled":
        return
    # Keep the final command output on this private Mac even on failure. It is
    # essential for diagnosing a local Brush/Metal installation without ever
    # exposing paths or command output to the phone.
    (job.directory / "worker.log").write_text((output[0] or "")[-20_000:])
    if return_code != 0 or output[0] is None:
        raise RuntimeError("worker_command_failed")


async def process(job: Job) -> None:
    async with JOB_LOCK:
        try:
            if job.state == "cancelled":
                return
            job.state, job.progress = "training", 0.05
            dataset = job.directory / "dataset"
            output = job.directory / "brush-output"
            video = job.directory / "CasaReel-Walk3D.mp4"
            output.mkdir(parents=True, exist_ok=True)
            write_nerfstudio_dataset(job.directory / "capture", dataset)
            job.progress = 0.15
            await run_command(job, command(os.environ.get("BRUSH_TRAIN_COMMAND", ""), dataset=dataset, output=output, video=video))
            if job.state == "cancelled":
                return
            job.state, job.progress = "rendering", 0.85
            await run_command(job, command(os.environ.get("WALK3D_RENDER_COMMAND", ""), dataset=dataset, output=output, video=video))
            if not video.is_file() or video.stat().st_size == 0:
                raise RuntimeError("renderer_did_not_write_video")
            job.video, job.state, job.progress = video, "finished", 1.0
        except Exception as error:  # The API intentionally returns only a stable error code.
            if job.state != "cancelled":
                job.state, job.message = "failed", str(error)
                print(f"Walk 3D job {job.id} failed: {type(error).__name__}: {error}", flush=True)
        finally:
            job.process = None


def worker_is_ready() -> bool:
    """Reject captures before upload while either required local command is absent."""
    return bool(os.environ.get("BRUSH_TRAIN_COMMAND", "").strip()) and bool(os.environ.get("WALK3D_RENDER_COMMAND", "").strip())


@app.post("/v1/walk3d/jobs", dependencies=[Depends(require_token)], status_code=202)
async def create_job(request: Request) -> dict:
    if not worker_is_ready():
        raise HTTPException(status_code=503, detail="worker_not_ready")
    if request.headers.get("content-type", "").split(";", 1)[0].lower() not in {"application/zip", "application/x-zip-compressed", "application/octet-stream"}:
        raise HTTPException(status_code=415, detail="capture_must_be_zip")
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    job = Job(id=str(uuid.uuid4()), directory=DATA_DIR / str(uuid.uuid4()))
    job.directory.mkdir(mode=0o700)
    archive = job.directory / "capture.zip"
    size = 0
    with archive.open("wb") as destination:
        async for chunk in request.stream():
            size += len(chunk)
            if size > MAX_CAPTURE_BYTES:
                destination.close()
                archive.unlink(missing_ok=True)
                shutil.rmtree(job.directory, ignore_errors=True)
                raise HTTPException(status_code=413, detail="capture_too_large")
            destination.write(chunk)
    capture_directory = job.directory / "capture"
    capture_directory.mkdir()
    try:
        safe_extract(archive, capture_directory)
    except (ValueError, zipfile.BadZipFile) as error:
        # This stays only on the private Mac; the phone receives the stable error code.
        print(f"Rejected Walk 3D capture: {type(error).__name__}: {error}", flush=True)
        shutil.rmtree(job.directory, ignore_errors=True)
        raise HTTPException(status_code=422, detail="invalid_capture") from error
    JOBS[job.id] = job
    asyncio.create_task(process(job))
    return job.response()


@app.get("/v1/walk3d/jobs/{job_id}", dependencies=[Depends(require_token)])
async def status(job_id: str) -> dict:
    return job_or_404(job_id).response()


@app.get("/v1/walk3d/jobs/{job_id}/video", dependencies=[Depends(require_token)])
async def video(job_id: str) -> FileResponse:
    job = job_or_404(job_id)
    if job.state != "finished" or job.video is None:
        raise HTTPException(status_code=409, detail="video_not_ready")
    return FileResponse(job.video, media_type="video/mp4", filename="CasaReel-Walk3D.mp4")


@app.delete("/v1/walk3d/jobs/{job_id}", dependencies=[Depends(require_token)], status_code=204)
async def cancel(job_id: str) -> None:
    job = job_or_404(job_id)
    # The app can send DELETE while its async stream is closing, including just
    # after a worker failure. Retain all files for the local test window so the
    # renderer log is never lost to that race. A future retention task cleans
    # these private job folders; this endpoint only stops active work.
    if job.state not in {"finished", "failed", "cancelled"}:
        job.state = "cancelled"
        if job.process is not None:
            job.process.terminate()
