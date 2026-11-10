@preconcurrency import AVFoundation
import CoreVideo
import Foundation
import simd
import Testing
@testable import Walk3DKit

/// Builds `.splat` records like `convert.py` does.
func splatRecord(position: SIMD3<Float>, scale: SIMD3<Float>, rgba: (UInt8, UInt8, UInt8, UInt8), rotation: (UInt8, UInt8, UInt8, UInt8) = (255, 128, 128, 128)) -> Data {
    var data = Data()
    for value in [position.x, position.y, position.z, scale.x, scale.y, scale.z] {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
    }
    data.append(contentsOf: [rgba.0, rgba.1, rgba.2, rgba.3, rotation.0, rotation.1, rotation.2, rotation.3])
    return data
}

/// path.json with a straight walk along +z, looking forward, y down (OpenCV).
func pathJSON(positions: [SIMD3<Float>]) -> Data {
    let poses = positions.enumerated().map { index, p in
        #"{"image":"video_01/frame_\#(index).jpg","position":[\#(p.x),\#(p.y),\#(p.z)],"rotation":[[1,0,0],[0,1,0],[0,0,1]],"fov_y":1.0,"aspect":0.5625}"#
    }.joined(separator: ",")
    return Data(#"{"format":"casareel-walk3d-path","version":1,"segments":[{"name":"capture","frames":[\#(poses)]}]}"#.utf8)
}

struct SplatSceneTests {
    @Test func gpuLayoutMatchesTheShader() {
        #expect(MemoryLayout<SplatScene.GPUSplat>.stride == 40)
    }

    @Test func parsesRecordsAndBuildsCovariance() throws {
        let data = splatRecord(position: [1, 2, 3], scale: [1, 2, 3], rgba: (255, 0, 0, 200))
        let scene = try SplatScene(data: data)
        #expect(scene.count == 1)
        let splat = scene.splats[0]
        #expect(splat.position == (1, 2, 3))
        #expect(splat.color == 0xC8_00_00_FF)
        let c = splat.covariance
        #expect(abs(c.0 - 1) < 1e-4 && abs(c.3 - 4) < 1e-4 && abs(c.5 - 9) < 1e-4)
        #expect(abs(c.1) < 1e-4 && abs(c.2) < 1e-4 && abs(c.4) < 1e-4)
    }

    @Test func rotationTurnsTheCovariance() {
        // 90° about z swaps the x and y extents.
        let quarter = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        let c = SplatScene.covariance(scale: [1, 3, 1], rotation: quarter)
        #expect(abs(c.0 - 9) < 1e-3 && abs(c.3 - 1) < 1e-3)
    }

    @Test func rejectsBrokenData() {
        #expect(throws: Walk3DImportError.invalidScene) { try SplatScene(data: Data()) }
        #expect(throws: Walk3DImportError.invalidScene) { try SplatScene(data: Data(count: 31)) }
        #expect(throws: Walk3DImportError.invalidScene) { try SplatScene(data: splatRecord(position: [.nan, 0, 0], scale: [1, 1, 1], rgba: (0, 0, 0, 0))) }
    }
}

struct CameraPathTests {
    @Test func walkMovesAtConstantSpeedAndLevelsTheHorizon() throws {
        // Uneven spacing: the camera paused near z = 1.
        let positions: [SIMD3<Float>] = [[0, 0, 0], [0, 0, 1], [0, 0, 1.01], [0, 0, 1.02], [0, 0, 3]]
        let path = try CameraPath(data: pathJSON(positions: positions))
        let walk = path.walk(frameCount: 11, smoothing: 0)
        #expect(walk.count == 11)
        let steps = zip(walk, walk.dropFirst()).map { simd_distance($0.position, $1.position) }
        #expect(steps.allSatisfy { abs($0 - 0.3) < 1e-3 }, "\(steps)")
        #expect(walk.allSatisfy { simd_distance($0.up, [0, -1, 0]) < 1e-4 }, "OpenCV y is down, so up is −y")
        #expect(walk.first?.position == [0, 0, 0] && walk.last.map { simd_distance($0.position, [0, 0, 3]) < 1e-4 } == true)
    }

    @Test func rejectsUnknownOrTooShortPaths() {
        #expect(throws: Walk3DImportError.invalidPath) { try CameraPath(data: Data("{}".utf8)) }
        #expect(throws: Walk3DImportError.invalidPath) { try CameraPath(data: pathJSON(positions: [[0, 0, 0]])) }
    }
}

struct SplatRendererTests {
    private func buffer(width: Int = 64, height: Int = 64) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [
            kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
        ] as CFDictionary, &buffer)
        return try #require(buffer)
    }

    /// (r, g, b) at a pixel of a BGRA buffer.
    private func pixel(_ buffer: CVPixelBuffer, x: Int, y: Int) -> (Int, Int, Int) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return (0, 0, 0) }
        let bytes = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer) + x * 4).assumingMemoryBound(to: UInt8.self)
        return (Int(bytes[2]), Int(bytes[1]), Int(bytes[0]))
    }

    private let camera = CameraPose(position: [0, 0, 0], forward: [0, 0, 1], up: [0, -1, 0], fovY: 1.2)

    @Test func drawsASplatInFrontOfTheCameraAndNothingBehindIt() throws {
        let scene = try SplatScene(data: splatRecord(position: [0, 0, 2], scale: [0.2, 0.2, 0.2], rgba: (255, 0, 0, 255)))
        let renderer = try SplatRenderer(scene: scene)
        let image = try buffer()
        try renderer.render(camera, into: image)
        let center = pixel(image, x: 32, y: 32), corner = pixel(image, x: 1, y: 1)
        #expect(center.0 > 200 && center.1 < 40 && center.2 < 40, "\(center)")
        #expect(corner.0 < 30, "\(corner)")

        var behind = camera
        behind.forward = [0, 0, -1]
        try renderer.render(behind, into: image)
        #expect(pixel(image, x: 32, y: 32).0 < 30)
    }

    @Test func screenAxesFollowTheCamera() throws {
        // A green splat to the camera's right (+x) and above it (−y in OpenCV) lands top right on screen.
        let scene = try SplatScene(data: splatRecord(position: [0.6, -0.6, 2], scale: [0.1, 0.1, 0.1], rgba: (0, 255, 0, 255)))
        let renderer = try SplatRenderer(scene: scene)
        let image = try buffer()
        try renderer.render(camera, into: image)
        // focal = 32 / tan(0.6) ≈ 46.8 px; offset 0.3 × 46.8 ≈ 14 px from the center.
        #expect(pixel(image, x: 46, y: 18).1 > 150)
        #expect(pixel(image, x: 18, y: 46).1 < 30)
    }

    @Test func sortsFarthestFirst() throws {
        let data = [Float(1), 5, 3].reduce(into: Data()) { $0 += splatRecord(position: [0, 0, $1], scale: [0.1, 0.1, 0.1], rgba: (9, 9, 9, 255)) }
            + splatRecord(position: [0, 0, -4], scale: [0.1, 0.1, 0.1], rgba: (9, 9, 9, 255))
        let renderer = try SplatRenderer(scene: try SplatScene(data: data))
        #expect(renderer.sortBackToFront(eye: .zero, forward: [0, 0, 1]) == 3, "the splat behind the camera is skipped")
    }

    @Test func nearerSplatCoversTheFartherOne() throws {
        let data = splatRecord(position: [0, 0, 2], scale: [0.2, 0.2, 0.2], rgba: (0, 0, 255, 255))
            + splatRecord(position: [0, 0, 4], scale: [0.4, 0.4, 0.4], rgba: (255, 0, 0, 255))
        let renderer = try SplatRenderer(scene: try SplatScene(data: data))
        let image = try buffer()
        try renderer.render(camera, into: image)
        let center = pixel(image, x: 32, y: 32)
        #expect(center.2 > 200 && center.0 < 60, "\(center)")
    }
}

struct Walk3DVideoRendererTests {
    @Test func rendersAWalkVideoFromATrainedScene() async throws {
        let fixtures = try MediaFixtures()
        let source = fixtures.directory.appending(path: "result", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        // A corridor of colored splats along the walk.
        var splats = Data()
        for z in stride(from: Float(1), through: 8, by: 0.5) {
            splats += splatRecord(position: [-0.8, 0, z], scale: [0.2, 0.2, 0.2], rgba: (255, 80, 0, 230))
            splats += splatRecord(position: [0.8, 0, z], scale: [0.2, 0.2, 0.2], rgba: (0, 120, 255, 230))
        }
        try splats.write(to: source.appending(path: "scene.splat"))
        try pathJSON(positions: (0..<20).map { [0, 0, Float($0) * 0.2] }).write(to: source.appending(path: "path.json"))

        let renderer = Walk3DVideoRenderer(workDirectory: fixtures.directory.appending(path: "renders"))
        var video: Walk3DVideo?
        for try await event in renderer.render(scene: TrainedScene(directory: source, gaussians: 30), options: .init(width: 180, height: 320, fps: 10)) {
            if case .finished(let finished) = event { video = finished }
        }
        let output = try #require(video)
        #expect(output.durationMs == 12_000, "20 poses × 0.25 s is below the 12 s minimum")
        let duration = try await AVURLAsset(url: output.fileURL).load(.duration).seconds
        #expect(abs(duration - 12) < 0.2)
    }

    @Test func rejectsAMissingScene() async throws {
        let fixtures = try MediaFixtures()
        let renderer = Walk3DVideoRenderer(workDirectory: fixtures.directory.appending(path: "renders"))
        await #expect(throws: Walk3DRenderError.invalidScene(.invalidScene)) {
            for try await _ in renderer.render(scene: TrainedScene(directory: fixtures.directory, gaussians: 0)) {}
        }
    }

    @Test func durationScalesWithPosesWithinLimits() {
        #expect(Walk3DVideoRenderer.durationSeconds(keyframes: 10) == 12)
        #expect(Walk3DVideoRenderer.durationSeconds(keyframes: 120) == 30)
        #expect(Walk3DVideoRenderer.durationSeconds(keyframes: 1_000) == 45)
    }
}
