"""Tests for convert.py with synthetic data: python3 -m unittest test_convert"""
import json
import math
import os
import struct
import tempfile
import unittest

import convert


def write_ply(path, rows):
    names = ["x", "y", "z", "nx", "ny", "nz", "f_dc_0", "f_dc_1", "f_dc_2", "opacity",
             "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3"]
    header = "ply\nformat binary_little_endian 1.0\nelement vertex %d\n" % len(rows)
    header += "".join("property float %s\n" % name for name in names) + "end_header\n"
    with open(path, "wb") as out:
        out.write(header.encode("ascii"))
        for row in rows:
            out.write(struct.pack("<%df" % len(names), *row))


class ConvertTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()

    def test_splat_records_are_decoded_filtered_and_sorted(self):
        big = [1, 2, 3, 0, 0, 0, 0, 0, 0, 2.0, 0, 0, 0, 1, 0, 0, 0]               # gray, alpha 0.88, scale 1
        small = [4, 5, 6, 0, 0, 0, 1.77, 0, -1.77, 2.0, -2, -2, -2, 0, 0, 0, 2]  # reddish, tiny
        invisible = [0, 0, 0, 0, 0, 0, 0, 0, 0, -10.0, 0, 0, 0, 1, 0, 0, 0]
        ply = os.path.join(self.dir, "in.ply")
        write_ply(ply, [small, invisible, big])
        out = os.path.join(self.dir, "scene.splat")
        self.assertEqual(convert.write_splat(ply, out), 2)
        with open(out, "rb") as handle:
            data = handle.read()
        self.assertEqual(len(data), 64)
        first = struct.unpack("<3f3f4B4B", data[:32])
        self.assertEqual(first[:3], (1.0, 2.0, 3.0))                      # the big one comes first
        self.assertAlmostEqual(first[3], 1.0, places=5)                   # exp(0)
        self.assertEqual(first[6:9], (128, 128, 128))                     # f_dc 0 -> mid gray
        self.assertEqual(first[9], round(convert.sigmoid(2.0) * 255))
        self.assertEqual(first[10:14], (255, 128, 128, 128))              # identity quaternion
        second = struct.unpack("<3f3f4B4B", data[32:])
        self.assertGreater(second[6], 240)
        self.assertLess(second[8], 15)
        self.assertEqual(second[10:14], (128, 128, 128, 255))             # normalized (0,0,0,1)

    def test_rejects_non_splat_ply(self):
        ply = os.path.join(self.dir, "points.ply")
        with open(ply, "wb") as out:
            out.write(b"ply\nformat binary_little_endian 1.0\nelement vertex 1\nproperty float x\nend_header\n")
            out.write(struct.pack("<f", 1))
        with self.assertRaises(ValueError):
            convert.write_splat(ply, os.path.join(self.dir, "x.splat"))

    def test_poses_become_camera_to_world_segments(self):
        with open(os.path.join(self.dir, "cameras.txt"), "w") as out:
            out.write("# Camera list\n1 PINHOLE 1000 2000 1000 1000 500 1000\n2 PINHOLE 1600 1200 1200 1200 800 600\n")
        # 90 degrees about y: q = (cos 45, 0, sin 45, 0); translation (1, 0, 0) in camera coordinates.
        c, s = math.cos(math.pi / 4), math.sin(math.pi / 4)
        with open(os.path.join(self.dir, "images.txt"), "w") as out:
            out.write("# Image list\n")
            out.write("2 1 0 0 0 0 0 -2 1 video_01/frame_00002.jpg\n\n")
            out.write("1 %f 0 %f 0 1 0 0 1 video_01/frame_00001.jpg\n1.0 2.0 -1\n" % (c, s))
            out.write("3 1 0 0 0 0 0 0 2 photos/photo_001.jpg\n\n")
        cameras = convert.read_cameras(os.path.join(self.dir, "cameras.txt"))
        path = convert.build_path(convert.read_images(os.path.join(self.dir, "images.txt"), cameras))
        self.assertEqual([s["name"] for s in path["segments"]], ["video_01"])
        frames = path["segments"][0]["frames"]
        self.assertEqual([f["image"] for f in frames], ["video_01/frame_00001.jpg", "video_01/frame_00002.jpg"])
        # Rotated camera: center = -R^T t. R maps x -> -z, so R^T (1,0,0) = (0,0,1) and the center is (0,0,-1).
        for got, want in zip(frames[0]["position"], [0, 0, -1]):
            self.assertAlmostEqual(got, want, places=5)
        self.assertEqual(frames[1]["position"], [0, 0, 2])
        self.assertAlmostEqual(frames[0]["fov_y"], 2 * math.atan(1.0))
        self.assertEqual(len(path["photos"]), 1)
        json.dumps(path)


if __name__ == "__main__":
    unittest.main()
