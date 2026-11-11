import Foundation
import simd
import Testing
@testable import Walk3DKit

struct KeyframeSelectorTests {
    private let forward = SIMD3<Float>(0, 0, 1)

    @Test func keepsTheFirstFrame() {
        var selector = KeyframeSelector()
        let kept1 = selector.keep(time: 0, position: .zero, forward: forward)
        #expect(kept1)
    }

    @Test func dropsFramesWhileStandingStill() {
        var selector = KeyframeSelector()
        _ = selector.keep(time: 0, position: .zero, forward: forward)
        let kept2 = selector.keep(time: 1, position: SIMD3(0.01, 0, 0), forward: forward)
        #expect(!kept2)
        #expect(selector.count == 1)
    }

    @Test func keepsAfterWalkingOrTurning() {
        var selector = KeyframeSelector()
        _ = selector.keep(time: 0, position: .zero, forward: forward)
        let kept3 = selector.keep(time: 0.5, position: SIMD3(0, 0, 0.2), forward: forward)
        #expect(kept3)
        let turned = simd_normalize(SIMD3<Float>(0.3, 0, 1))
        let kept4 = selector.keep(time: 1, position: SIMD3(0, 0, 0.2), forward: turned)
        #expect(kept4)
    }

    @Test func respectsTheMinimumInterval() {
        var selector = KeyframeSelector()
        _ = selector.keep(time: 0, position: .zero, forward: forward)
        let kept5 = selector.keep(time: 0.05, position: SIMD3(0, 0, 1), forward: forward)
        #expect(!kept5)
    }

    @Test func stopsWhenFull() {
        var selector = KeyframeSelector(maxKeyframes: 2)
        _ = selector.keep(time: 0, position: .zero, forward: forward)
        _ = selector.keep(time: 1, position: SIMD3(0, 0, 1), forward: forward)
        #expect(selector.isFull)
        let kept6 = selector.keep(time: 2, position: SIMD3(0, 0, 2), forward: forward)
        #expect(!kept6)
    }

    @Test func rejectsNonFinitePoses() {
        var selector = KeyframeSelector()
        let kept7 = selector.keep(time: 0, position: SIMD3(.nan, 0, 0), forward: forward)
        #expect(!kept7)
    }
}

struct PointCloudTests {
    @Test func latestPositionWinsPerIdentifier() throws {
        var cloud = PointCloudAccumulator()
        cloud.add(identifiers: [1, 2], positions: [SIMD3(0, 0, 0), SIMD3(1, 1, 1)])
        cloud.add(identifiers: [1], positions: [SIMD3(0, 0, 0.5)])
        #expect(cloud.points.count == 2)
        #expect(cloud.points[1] == SIMD3(0, 0, 0.5))
    }

    @Test func roundTripsAndDropsNonFinite() throws {
        var cloud = PointCloudAccumulator()
        cloud.add(identifiers: [1, 2], positions: [SIMD3(1, 2, 3), SIMD3(.infinity, 0, 0)])
        let decoded = try PointCloudAccumulator.decode(cloud.encoded())
        #expect(decoded == [SIMD3(1, 2, 3)])
    }

    @Test func rejectsTruncatedFiles() {
        #expect(throws: SceneCaptureError.invalidCapture) { try PointCloudAccumulator.decode(Data(count: 13)) }
    }
}

struct CaptureManifestTests {
    private static func camera() -> CapturedCamera {
        CapturedCamera(fx: 1400, fy: 1400, cx: 959.5, cy: 719.5, width: 1920, height: 1440,
                       cameraToWorld: simd_float4x4(SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(1, 2, 3, 1)))
    }

    @Test func arkitLooksAlongMinusZAndOpenCVAlongPlusZ() {
        let converted = CapturedCamera.openCVCameraToWorld(arkit: matrix_identity_float4x4)
        let camera = CapturedCamera(fx: 1, fy: 1, cx: 0, cy: 0, width: 16, height: 16, cameraToWorld: converted)
        #expect(camera.forward == SIMD3(0, 0, -1))
        // Image y (down) must point to world −y when ARKit's camera is upright.
        #expect(converted.columns.1 == SIMD4(0, -1, 0, 0))
    }

    @Test func halvingTheImageHalvesTheIntrinsics() {
        let scaled = Self.camera().scaled(by: 0.5, width: 960, height: 720)
        #expect(scaled.fx == 700)
        #expect(scaled.cx == 479.5)
        #expect(scaled.width == 960)
    }

    @Test func roundTrips() throws {
        let frames = (1...CaptureManifest.minKeyframes).map { CaptureManifest.frame(image: "frame_\($0).jpg", camera: Self.camera()) }
        let manifest = CaptureManifest(frames: frames, pointCount: 10)
        let loaded = try CaptureManifest.load(from: manifest.encoded())
        #expect(loaded == manifest)
        #expect(loaded.frames[0].camera == Self.camera())
    }

    @Test func rejectsTooFewFrames() throws {
        let manifest = CaptureManifest(frames: [CaptureManifest.frame(image: "frame_1.jpg", camera: Self.camera())], pointCount: 0)
        #expect(throws: SceneCaptureError.invalidCapture) { try CaptureManifest.load(from: manifest.encoded()) }
    }

    @Test func rejectsPathTraversal() throws {
        var frames = (1...CaptureManifest.minKeyframes).map { CaptureManifest.frame(image: "frame_\($0).jpg", camera: Self.camera()) }
        frames[0] = CaptureManifest.frame(image: "../secret.jpg", camera: Self.camera())
        #expect(throws: SceneCaptureError.invalidCapture) { try CaptureManifest.load(from: CaptureManifest(frames: frames, pointCount: 0).encoded()) }
    }
}

struct RemoteCaptureArchiveTests {
    @Test func writesCentralDirectoryAtTheOffsetRecordedInTheZipTrailer() throws {
        let fixtures = try MediaFixtures()
        let frames = fixtures.directory.appending(path: "frames", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: fixtures.directory.appending(path: "capture.json"))
        try Data([0, 1, 2, 3]).write(to: fixtures.directory.appending(path: "points.bin"))
        for index in 0..<20 {
            try Data([UInt8(index)]).write(to: frames.appending(path: String(format: "frame_%05d.jpg", index)))
        }

        let archive = fixtures.directory.deletingLastPathComponent().appending(path: "walk3d.zip")
        try RemoteCaptureArchive.write(directory: fixtures.directory, to: archive)
        let bytes = try Data(contentsOf: archive)

        // End-of-central-directory is 22 bytes because this archive has no ZIP comment.
        let trailer = bytes.count - 22
        #expect(Array(bytes[trailer..<(trailer + 4)]) == [0x50, 0x4B, 0x05, 0x06])
        let offset = bytes[(trailer + 16)..<(trailer + 20)].enumerated().reduce(UInt32(0)) { partial, item in
            partial | (UInt32(item.element) << UInt32(item.offset * 8))
        }
        let central = Int(offset)
        #expect(Array(bytes[central..<(central + 4)]) == [0x50, 0x4B, 0x01, 0x02])
    }
}
