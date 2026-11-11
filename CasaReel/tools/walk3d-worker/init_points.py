"""ARKit feature points -> `init.ply`, the starting point cloud Brush uses when it sits in the dataset folder."""
import math
import struct
from pathlib import Path

MAX_POINTS = 150_000


def read_points(path: Path):
    data = path.read_bytes()
    if len(data) % 12 or len(data) > MAX_POINTS * 12:
        raise ValueError("invalid_points_file")
    return [p for p in struct.iter_unpack("<3f", data) if all(math.isfinite(v) for v in p)]


def write_init_ply(points, destination: Path, gray: int = 128) -> int:
    header = ("ply\nformat binary_little_endian 1.0\n"
              f"element vertex {len(points)}\n"
              "property float x\nproperty float y\nproperty float z\n"
              "property uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n")
    with destination.open("wb") as out:
        out.write(header.encode())
        for x, y, z in points:
            out.write(struct.pack("<3f3B", x, y, z, gray, gray, gray))
    return len(points)
