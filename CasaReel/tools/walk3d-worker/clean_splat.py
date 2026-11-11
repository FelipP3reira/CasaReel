#!/usr/bin/env python3
"""Removes "needle" Gaussians from a Brush PLY before it is rendered.

Training sometimes grows Gaussians that are very long and thin (or simply huge). Seen from the walk's camera
they are the white or colored streaks that veil the room. Two limits, applied to every splat:

- the longest axis is at most MAX_ANISOTROPY times the second longest (flat discs, which walls and floors are
  made of, are untouched: their two long axes are similar);
- no axis is longer than MAX_AXIS meters (a splat that big is a floater, not a surface).

Brush stores scales as natural logs, so both limits are applied to the logs. Everything else in the file
(positions, colors, opacity, rotation, spherical harmonics) is copied byte for byte.
"""
import math
import struct
import sys
from pathlib import Path

MAX_ANISOTROPY = 6.0
MAX_AXIS = 1.0


def clean(source: Path, destination: Path, max_anisotropy: float = MAX_ANISOTROPY, max_axis: float = MAX_AXIS) -> dict:
    data = bytearray(Path(source).read_bytes())
    marker = data.index(b"end_header\n") + len(b"end_header\n")
    header = data[:marker].decode("ascii").splitlines()
    properties = [line.split()[-1] for line in header if line.startswith("property")]
    count = int(next(line for line in header if line.startswith("element vertex")).split()[-1])
    slots = [properties.index(f"scale_{axis}") for axis in range(3)]
    stride = len(properties) * 4
    if len(data) - marker != count * stride or any(not line.split()[1] == "float" for line in header if line.startswith("property")):
        raise ValueError("unsupported_ply_layout")
    log_ratio, log_axis = math.log(max_anisotropy), math.log(max_axis)
    shortened = capped = 0
    for index in range(count):
        base = marker + index * stride
        original = [struct.unpack_from("<f", data, base + 4 * slot)[0] for slot in slots]
        scales = original if all(math.isfinite(value) for value in original) else [log_axis] * 3
        limited = [min(value, log_axis) for value in scales]
        ordered = sorted(limited)
        # Longest axis no more than log_ratio above the second longest.
        limited = [min(value, ordered[1] + log_ratio) for value in limited]
        capped += any(a > log_axis for a in scales)
        shortened += limited != [min(value, log_axis) for value in scales]
        if limited != original:
            for slot, value in zip(slots, limited):
                struct.pack_into("<f", data, base + 4 * slot, value)
    Path(destination).write_bytes(data)
    return {"splats": count, "capped": capped, "shortened": shortened}


if __name__ == "__main__":
    print(clean(Path(sys.argv[1]), Path(sys.argv[2])))
