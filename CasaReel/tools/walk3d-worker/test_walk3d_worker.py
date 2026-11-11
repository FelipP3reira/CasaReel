"""Run: .venv/bin/python -m unittest test_walk3d_worker -v   (from this folder)"""
import json
import math
import struct
import tempfile
import unittest
from pathlib import Path

import init_points
import make_camera_track as track


def frame(position, forward_gl=(0.0, 0.0, -1.0)):
    """ARKit/OpenGL camera: looks along local -z, so the matrix's z column is -forward. Identity rotation."""
    return {"transform_matrix": [[1, 0, 0, position[0]], [0, 1, 0, position[1]], [0, 0, 1, position[2]], [0, 0, 0, 1]]}


class InitPointsTests(unittest.TestCase):
    def test_writes_a_ply_brush_can_read_and_drops_non_finite_points(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "points.bin"
            source.write_bytes(struct.pack("<9f", 1, 2, 3, math.nan, 0, 0, 4, 5, 6))
            points = init_points.read_points(source)
            self.assertEqual(points, [(1, 2, 3), (4, 5, 6)])
            out = Path(folder) / "init.ply"
            self.assertEqual(init_points.write_init_ply(points, out), 2)
            data = out.read_bytes()
            header, body = data.split(b"end_header\n")
            self.assertIn(b"element vertex 2", header)
            self.assertEqual(len(body), 2 * (12 + 3))
            self.assertEqual(struct.unpack_from("<3f", body), (1.0, 2.0, 3.0))

    def test_rejects_a_truncated_file(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / "points.bin"
            source.write_bytes(b"\0" * 13)
            with self.assertRaises(ValueError):
                init_points.read_points(source)


class CameraTrackTests(unittest.TestCase):
    frames = [frame((0.1 * i, 0.0, 0.0)) for i in range(30)]

    def test_track_lives_in_the_viewer_frame_supersplat_uses(self):
        # Regression: raw dataset coordinates put the camera outside the scene and every video frame was black.
        # SuperSplat turns a loaded PLY 180 degrees around Z, so (x, y, z) must become (-x, -y, z).
        built = track.build_track(self.frames, width=960, fl_x=720)
        # The start is smoothed over the first 7 keyframes (x = 0.0 ... 0.6, mean 0.3), then mirrored.
        self.assertAlmostEqual(built[0]["position"][0], -0.3, places=6)
        self.assertLess(built[-1]["position"][0], -2.0)  # walked toward +x in the dataset
        for item in built:
            self.assertAlmostEqual(item["position"][1], 0.0, places=6)

    def test_the_horizon_stays_level_whatever_the_sensor_roll(self):
        rolled = [{"transform_matrix": [[0, 1, 0, 0.1 * i], [-1, 0, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]} for i in range(30)]
        built = track.build_track(rolled, width=960, fl_x=720)
        self.assertTrue(all(item["up"] == [-0.0, -1.0, 0.0] or item["up"] == [0.0, -1.0, 0.0] for item in built))

    def test_the_camera_looks_where_the_phone_looked(self):
        built = track.build_track(self.frames, width=960, fl_x=720)
        first = built[0]
        direction = [t - p for t, p in zip(first["target"], first["position"])]
        # Identity rotation looks along -z in the dataset; the viewer frame only flips x and y, so still -z.
        self.assertAlmostEqual(direction[2], -1.0, places=5)
        self.assertAlmostEqual(direction[0], 0.0, places=5)

    def test_constant_speed_and_portrait_field_of_view(self):
        built = track.build_track(self.frames, width=960, fl_x=720)
        steps = [track.length(track.sub(b["position"], a["position"])) for a, b in zip(built, built[1:])]
        self.assertLess(max(steps) - min(steps), 1e-6)
        self.assertAlmostEqual(built[0]["fov"], math.degrees(2 * math.atan(960 / (2 * 720))), places=6)

    def test_length_follows_keyframes_within_limits(self):
        self.assertEqual(len(track.build_track(self.frames, 960, 720)), 12 * 24)
        many = [frame((0.1 * i, 0, 0)) for i in range(240)]
        self.assertEqual(len(track.build_track(many, 960, 720)), 45 * 24)

    def test_cli_writes_a_supersplat_track(self):
        with tempfile.TemporaryDirectory() as folder:
            dataset = Path(folder)
            (dataset / "transforms.json").write_text(json.dumps({"w": 960, "h": 720, "fl_x": 720, "frames": self.frames}))
            import subprocess, sys
            out = dataset / "camera.json"
            subprocess.run([sys.executable, str(Path(track.__file__)), str(dataset), str(out)], check=True)
            written = json.loads(out.read_text())
            self.assertEqual(written["frameRate"], 24)
            self.assertTrue(all({"position", "target", "up", "fov"} <= set(item) for item in written["frames"]))


class TrimmingTests(unittest.TestCase):
    """A wall at z = -3 (cameras look along -z). Cameras at z = -2.5 are 0.5 m from it, cameras at z = 0 are 3 m away."""
    wall = [(x * 0.1, y * 0.1, -3.0) for x in range(-50, 51) for y in range(-20, 21)]

    @staticmethod
    def walk(zs):
        return [frame((0.1 * i, 0.0, z)) for i, z in enumerate(zs)]

    def keyframes(self, frames):
        return [([m["transform_matrix"][i][3] for i in range(3)], [0.0, 0.0, -1.0]) for m in frames]

    def test_clearance_is_the_distance_to_the_surface_ahead(self):
        near = track.clearance([0, 0, -2.5], [0, 0, -1], self.wall)
        far = track.clearance([0, 0, 0], [0, 0, -1], self.wall)
        self.assertAlmostEqual(near, 0.5, delta=0.1)
        self.assertAlmostEqual(far, 3.0, delta=0.25)  # a percentile of a cone: off-axis points are a bit farther
        self.assertIsNone(track.clearance([0, 0, 0], [0, 0, 1], self.wall))  # looking away: nothing ahead

    def test_the_cramped_opening_is_cut(self):
        frames = self.walk([-2.5] * 12 + [0.0] * 28)
        start, end = track.good_stretch(self.keyframes(frames), self.wall)
        self.assertEqual((start, end), (12, 40))

    def test_the_cramped_ending_is_cut_too(self):
        frames = self.walk([0.0] * 28 + [-2.5] * 12)
        self.assertEqual(track.good_stretch(self.keyframes(frames), self.wall), (0, 28))

    def test_a_short_gap_does_not_split_a_good_stretch(self):
        frames = self.walk([0.0] * 10 + [-2.5] * 2 + [0.0] * 10 + [-2.5] * 18)
        self.assertEqual(track.good_stretch(self.keyframes(frames), self.wall), (0, 22))

    def test_a_small_home_keeps_the_whole_walk(self):
        frames = self.walk([-2.5] * 30 + [0.0] * 6)  # only 6 of 36 keyframes have room: under the 12-keyframe minimum
        self.assertEqual(track.good_stretch(self.keyframes(frames), self.wall), (0, 36))

    def test_without_points_nothing_is_cut(self):
        frames = self.walk([-2.5] * 30)
        self.assertEqual(track.good_stretch(self.keyframes(frames), []), (0, 30))
        self.assertEqual(len(track.build_track(frames, 960, 720)), 12 * 24)

    def test_the_track_starts_where_the_good_stretch_starts(self):
        frames = self.walk([-2.5] * 12 + [0.0] * 28)
        trimmed = track.build_track(frames, 960, 720, self.wall)
        untrimmed = track.build_track(frames, 960, 720)
        # Keyframe 12 sits at x = 1.2; the viewer frame mirrors x. The full walk starts around x = 0.3.
        self.assertLess(trimmed[0]["position"][0], untrimmed[0]["position"][0] - 0.5)

    def test_init_ply_points_are_read_back(self):
        with tempfile.TemporaryDirectory() as folder:
            init_points.write_init_ply([(1.0, 2.0, 3.0), (4.0, 5.0, 6.0)], Path(folder) / "init.ply")
            self.assertEqual(track.read_init_points(folder), [(1.0, 2.0, 3.0), (4.0, 5.0, 6.0)])
            self.assertEqual(track.read_init_points(Path(folder) / "missing"), [])


if __name__ == "__main__":
    unittest.main()
