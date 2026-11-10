#!/usr/bin/env python3
"""CasaReel Walk 3D: turns COLMAP poses + a Brush splat into what the iPhone app renders.

Standard library only (runs on the python3 that ships with the Xcode command line tools).

    python3 convert.py <brush.ply> <colmap_text_model_dir> <out_dir>

Writes:
  scene.splat  32 bytes per Gaussian, little endian:
               position 3 x float32, scale 3 x float32 (linear, not log),
               color RGBA 4 x uint8 (alpha = opacity), rotation 4 x uint8 (w, x, y, z mapped from [-1, 1] to [0, 255]).
               Sorted by importance (opacity x volume), largest first, capped at MAX_SPLATS.
  path.json    camera poses in COLMAP world coordinates (camera-to-world, OpenCV axes: x right, y down, z forward),
               one segment per video in time order, plus the photos.
"""
import json
import math
import os
import struct
import sys

SH_C0 = 0.28209479177387814
MAX_SPLATS = 1_000_000  # above this, iPhone render time roughly doubles (memory) for little visible gain
MIN_ALPHA = 0.02

PLY_TYPES = {
    "char": "b", "int8": "b", "uchar": "B", "uint8": "B",
    "short": "h", "int16": "h", "ushort": "H", "uint16": "H",
    "int": "i", "int32": "i", "uint": "I", "uint32": "I",
    "float": "f", "float32": "f", "double": "d", "float64": "d",
}


def read_ply_header(handle):
    if handle.readline().strip() != b"ply":
        raise ValueError("not a PLY file")
    count, properties, fmt, in_vertex = 0, [], None, False
    while True:
        line = handle.readline()
        if not line:
            raise ValueError("truncated PLY header")
        words = line.decode("ascii", "replace").split()
        if not words:
            continue
        if words[0] == "format":
            fmt = words[1]
        elif words[0] == "element":
            in_vertex = words[1] == "vertex"
            if in_vertex:
                count = int(words[2])
        elif words[0] == "property" and in_vertex:
            if words[1] == "list":
                raise ValueError("list properties in vertices are not supported")
            properties.append((words[2], PLY_TYPES[words[1]]))
        elif words[0] == "end_header":
            break
    if fmt != "binary_little_endian":
        raise ValueError("only binary_little_endian PLY is supported (got %s)" % fmt)
    return count, properties


def sigmoid(value):
    if value >= 0:
        return 1 / (1 + math.exp(-value))
    exp = math.exp(value)
    return exp / (1 + exp)


def clamp_byte(value):
    return max(0, min(255, int(round(value))))


def ply_to_splats(path):
    """Yields (importance, record_bytes) for each Gaussian worth keeping."""
    with open(path, "rb") as handle:
        count, properties = read_ply_header(handle)
        names = [name for name, _ in properties]
        required = ["x", "y", "z", "f_dc_0", "f_dc_1", "f_dc_2", "opacity",
                    "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3"]
        missing = [name for name in required if name not in names]
        if missing:
            raise ValueError("PLY is not a Gaussian splat (missing %s)" % ", ".join(missing))
        index = {name: names.index(name) for name in required}
        row = struct.Struct("<" + "".join(kind for _, kind in properties))
        data = handle.read(row.size * count)
        if len(data) < row.size * count:
            raise ValueError("truncated PLY data")
        record = struct.Struct("<3f3f4B4B")
        for values in row.iter_unpack(data):
            alpha = sigmoid(values[index["opacity"]])
            if alpha < MIN_ALPHA:
                continue
            position = [values[index[k]] for k in ("x", "y", "z")]
            scale = [math.exp(min(values[index[k]], 10)) for k in ("scale_0", "scale_1", "scale_2")]
            rotation = [values[index[k]] for k in ("rot_0", "rot_1", "rot_2", "rot_3")]
            if not all(math.isfinite(v) for v in position + scale + rotation):
                continue
            norm = math.sqrt(sum(v * v for v in rotation)) or 1.0
            color = [clamp_byte((0.5 + SH_C0 * values[index[k]]) * 255) for k in ("f_dc_0", "f_dc_1", "f_dc_2")]
            packed = record.pack(
                *position, *scale, *color, clamp_byte(alpha * 255),
                *[clamp_byte(v / norm * 128 + 128) for v in rotation],
            )
            yield alpha * scale[0] * scale[1] * scale[2], packed


def write_splat(ply_path, out_path):
    splats = sorted(ply_to_splats(ply_path), key=lambda item: -item[0])[:MAX_SPLATS]
    with open(out_path, "wb") as out:
        for _, packed in splats:
            out.write(packed)
    return len(splats)


def quaternion_to_matrix(w, x, y, z):
    return [
        [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
        [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
        [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)],
    ]


def data_lines(path):
    with open(path) as handle:
        return [line.rstrip("\n") for line in handle if not line.startswith("#")]


def read_cameras(path):
    cameras = {}
    for line in data_lines(path):
        words = line.split()
        if not words:
            continue
        camera_id, model, width, height = int(words[0]), words[1], int(words[2]), int(words[3])
        params = [float(v) for v in words[4:]]
        # PINHOLE: fx fy cx cy; the SIMPLE_* models start with a single f.
        focal_y = params[1] if model in ("PINHOLE", "OPENCV", "FULL_OPENCV", "OPENCV_FISHEYE") else params[0]
        cameras[camera_id] = {"width": width, "height": height, "fov_y": 2 * math.atan(height / (2 * focal_y))}
    return cameras


def read_images(path, cameras):
    """images.txt has two lines per image (the second, with 2D points, may be empty)."""
    lines = data_lines(path)
    poses = []
    for line in lines[0::2]:
        words = line.split()
        if len(words) < 10:
            continue
        qw, qx, qy, qz, tx, ty, tz = (float(v) for v in words[1:8])
        camera = cameras[int(words[8])]
        name = " ".join(words[9:])
        world_to_camera = quaternion_to_matrix(qw, qx, qy, qz)
        # Camera-to-world: R^T, and the camera center C = -R^T t.
        rotation = [[world_to_camera[j][i] for j in range(3)] for i in range(3)]
        center = [-sum(rotation[i][j] * (tx, ty, tz)[j] for j in range(3)) for i in range(3)]
        poses.append({"image": name, "position": center, "rotation": rotation,
                      "fov_y": camera["fov_y"], "aspect": camera["width"] / camera["height"]})
    return poses


def build_path(poses):
    segments = {}
    photos = []
    for pose in poses:
        folder = pose["image"].split("/")[0]
        if folder.startswith("video_"):
            segments.setdefault(folder, []).append(pose)
        else:
            photos.append(pose)
    return {
        "format": "casareel-walk3d-path",
        "version": 1,
        "coordinates": "colmap_opencv_camera_to_world",
        "segments": [{"name": name, "frames": sorted(frames, key=lambda p: p["image"])}
                     for name, frames in sorted(segments.items())],
        "photos": sorted(photos, key=lambda p: p["image"]),
    }


def main(argv):
    if len(argv) != 4:
        print(__doc__)
        return 2
    ply_path, model_dir, out_dir = argv[1:]
    os.makedirs(out_dir, exist_ok=True)
    cameras = read_cameras(os.path.join(model_dir, "cameras.txt"))
    path = build_path(read_images(os.path.join(model_dir, "images.txt"), cameras))
    with open(os.path.join(out_dir, "path.json"), "w") as out:
        json.dump(path, out)
    kept = write_splat(ply_path, os.path.join(out_dir, "scene.splat"))
    frames = sum(len(segment["frames"]) for segment in path["segments"])
    print("Gaussians kept: %d | video poses: %d | photo poses: %d" % (kept, frames, len(path["photos"])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
