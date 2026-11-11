#!/usr/bin/env python3
"""Turns the ARKit keyframe poses of a Walk 3D capture into a SuperSplat camera track.

Frames of reference (all verified by rendering, see `test_make_camera_track.py`):
- `transforms.json` is ARKit's gravity-aligned world (y up), OpenGL cameras (they look along local -z).
- SuperSplat rotates a loaded PLY by 180 degrees around Z, so the track has to be written in that rotated
  frame: (x, y, z) -> (-x, -y, z). Raw coordinates put the camera outside the scene and every frame is black.
- Keyframes are landscape sensor images whatever the phone's orientation, so the camera's own "up" is
  useless. The video keeps the horizon level instead: one world-up for the whole walk.
"""
import json, math, struct, sys
from pathlib import Path

FRAME_RATE = 24
FRAMES_MIN, FRAMES_MAX, SECONDS_PER_KEYFRAME = 12 * FRAME_RATE, 45 * FRAME_RATE, 0.25
SMOOTHING = 6

# Where the video starts and ends. A walk through a doorway or past furniture has stretches where the camera
# is a few centimeters from a surface; they render as a brown or white smear. Keep the longest stretch with
# room to see, judged by the distance to the ARKit feature points ahead of the camera.
MIN_CLEARANCE = 1.2          # meters to the nearest surface ahead
VIEW_CONE_DEGREES = 30
MIN_POINTS_AHEAD = 8         # fewer than this is a blank surface right in front of the lens: not clear
MAX_GAP = 2                  # keyframes that may fail inside a good stretch without ending it
MIN_KEPT_FRACTION = 0.25     # a shorter good stretch means the home is small (or the scan is all close-ups):
MIN_KEPT_KEYFRAMES = 12      # keep the whole walk instead of cutting it down to almost nothing
MAX_POINTS_USED = 20_000


def add(a, b): return [x + y for x, y in zip(a, b)]
def scale(a, s): return [x * s for x in a]
def sub(a, b): return [x - y for x, y in zip(a, b)]
def length(a): return math.sqrt(sum(x * x for x in a))
def normalize(a):
    n = length(a)
    return scale(a, 1 / n) if n > 1e-9 else a
def mix(a, b, t): return [x * (1 - t) + y * t for x, y in zip(a, b)]
def mean(vectors): return scale([sum(v[i] for v in vectors) for i in range(3)], 1 / len(vectors))
def to_viewer(v): return [-v[0], -v[1], v[2]]


def read_init_points(dataset):
    """Points from the `init.ply` the worker writes next to `transforms.json` (x, y, z floats + 3 color bytes)."""
    path = Path(dataset) / "init.ply"
    try:
        data = path.read_bytes()
        marker = data.index(b"end_header\n") + len(b"end_header\n")
    except (OSError, ValueError):
        return []
    header = data[:marker].decode("ascii", "ignore")
    if "property float x" not in header or "property uchar blue" not in header:
        return []
    count = (len(data) - marker) // 15
    step = max(1, count // MAX_POINTS_USED)
    return [struct.unpack_from("<3f", data, marker + i * 15) for i in range(0, count, step)]


def clearance(position, forward, points):
    """Distance to the nearest surface ahead (20th percentile of the points in a cone), or None if too few."""
    cosine = math.cos(math.radians(VIEW_CONE_DEGREES))
    ahead = []
    for point in points:
        offset = sub(list(point), position)
        distance = length(offset)
        if distance > 0.05 and sum(a * b for a, b in zip(offset, forward)) / distance > cosine:
            ahead.append(distance)
    if len(ahead) < MIN_POINTS_AHEAD:
        return None
    ahead.sort()
    return ahead[len(ahead) // 5]


def good_stretch(poses, points):
    """(start, end) keyframe indices of the longest stretch with room to see, or the whole walk if there is none."""
    whole = (0, len(poses))
    if not points or len(poses) < 2:
        return whole
    good = []
    for position, forward in poses:
        room = clearance(position, forward, points)
        good.append(room is not None and room >= MIN_CLEARANCE)
    best, start, last_good = (0, 0), None, None
    for index, ok in enumerate(good):
        if ok:
            if start is None or index - last_good > MAX_GAP + 1:
                start = index
            last_good = index
            if last_good + 1 - start > best[1] - best[0]:
                best = (start, last_good + 1)
    if best[1] - best[0] < max(MIN_KEPT_KEYFRAMES, MIN_KEPT_FRACTION * len(poses)):
        return whole
    return best


def build_track(frames, width, fl_x, points=None):
    """Smooth walk through the keyframes at constant speed, horizon level. `frames` are transforms.json frames."""
    poses = []
    for item in frames:
        m = item["transform_matrix"]
        poses.append(([m[i][3] for i in range(3)], normalize([-m[i][2] for i in range(3)])))
    start, end = good_stretch(poses, points)
    poses = poses[start:end]
    smoothed = []
    for index in range(len(poses)):
        window = poses[max(0, index - SMOOTHING):index + SMOOTHING + 1]
        forward = mean([p[1] for p in window])
        smoothed.append((mean([p[0] for p in window]), normalize(forward) if length(forward) > 1e-6 else poses[index][1]))
    # Portrait video from landscape sensor frames: the video's vertical field of view is the sensor's horizontal one.
    fov = math.degrees(2 * math.atan(width / (2 * fl_x)))
    distance = [0.0]
    for a, b in zip(smoothed, smoothed[1:]):
        distance.append(distance[-1] + length(sub(b[0], a[0])))
    total = distance[-1] or float(len(smoothed) - 1)
    if distance[-1] == 0:
        distance = [float(i) for i in range(len(smoothed))]
    count = int(min(max(len(poses) * SECONDS_PER_KEYFRAME * FRAME_RATE, FRAMES_MIN), FRAMES_MAX))
    world_up = [0.0, 1.0, 0.0]
    track, segment = [], 0
    for index in range(count):
        target = total * index / (count - 1)
        while segment < len(smoothed) - 2 and distance[segment + 1] < target:
            segment += 1
        span = distance[segment + 1] - distance[segment]
        t = min(max((target - distance[segment]) / span, 0.0), 1.0) if span else 0.0
        position = mix(smoothed[segment][0], smoothed[segment + 1][0], t)
        forward = normalize(mix(smoothed[segment][1], smoothed[segment + 1][1], t))
        track.append({"position": to_viewer(position), "target": to_viewer(add(position, forward)),
                      "up": to_viewer(world_up), "fov": fov})
    return track


def main():
    dataset, output = map(Path, sys.argv[1:3])
    source = json.loads((dataset / "transforms.json").read_text())
    track = build_track(source["frames"], source["w"], source["fl_x"], read_init_points(dataset))
    output.write_text(json.dumps({"frameRate": FRAME_RATE, "frames": track}))


if __name__ == "__main__":
    main()
