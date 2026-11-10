import CoreGraphics
import Foundation
import ImageIO
import simd
import Testing
import UniformTypeIdentifiers
@testable import Walk3DKit

/// A camera at the origin looking along +z (OpenCV axes), `width` × `height` pixels.
private func frontCamera(width: Int, height: Int, focal: Float) -> CapturedCamera {
    CapturedCamera(fx: focal, fy: focal, cx: Float(width - 1) / 2, cy: Float(height - 1) / 2,
                   width: width, height: height, cameraToWorld: matrix_identity_float4x4)
}

private func solidImage(width: Int, height: Int, rgb: (UInt8, UInt8, UInt8)) -> TrainingImage {
    TrainingImage(width: width, height: height, pixels: (0..<(width * height)).flatMap { _ in [rgb.0, rgb.1, rgb.2, 255] })
}

private let gradientsOnly = TrainingSession.Step(lrA: .zero, lrB: SIMD4(0, 1, 1, 0), counts: .zero)

struct TrainingGradientTests {
    /// Two overlapping anisotropic, rotated Gaussians in front of a black target: the loss is smooth there
    /// (every pixel is brighter than the target), so central differences are a fair reference.
    private static func model() -> GaussianModel {
        let rotation = simd_normalize(SIMD4<Float>(0.9, 0.2, -0.3, 0.25))
        var params = GaussianModel.gaussian(position: SIMD3(0.1, -0.05, 3), logScale: log(SIMD3(0.6, 0.4, 0.5)),
                                            rotation: rotation, color: SIMD3(0.8, 0.4, 0.6), opacity: 0.6)
        params += GaussianModel.gaussian(position: SIMD3(-0.1, 0.1, 3.5), logScale: log(SIMD3(0.5, 0.7, 0.4)),
                                         color: SIMD3(0.3, 0.7, 0.5), opacity: 0.5)
        return GaussianModel(params: params)
    }

    private static func loss(_ session: TrainingSession, _ model: GaussianModel) throws -> Float {
        session.upload(model)
        try session.run(viewIndex: 0, step: gradientsOnly)
        return session.loss()
    }

    @Test(arguments: [0, 2, 3, 4, 7, 8, 10, 13, 16, 18, 21, 29])
    func analyticGradientMatchesFiniteDifferences(parameter: Int) throws {
        let view = TrainingView(camera: frontCamera(width: 32, height: 32, focal: 30), background: SplatTrainer.background)
        let base = Self.model()
        let session = try TrainingSession(model: base, views: [view], images: [solidImage(width: 32, height: 32, rgb: (0, 0, 0))], capacity: 8)
        try session.run(viewIndex: 0, step: gradientsOnly)
        let analytic = session.gradients()[parameter]

        let epsilon: Float = 2e-3
        var plus = base, minus = base
        plus.params[parameter] += epsilon
        minus.params[parameter] -= epsilon
        let numeric = (try Self.loss(session, plus) - Self.loss(session, minus)) / (2 * epsilon)

        let tolerance = 0.08 * max(abs(numeric), abs(analytic)) + 2e-5
        #expect(abs(analytic - numeric) <= tolerance, "parameter \(parameter): analytic \(analytic), numeric \(numeric)")
    }
}

struct TrainingConvergenceTests {
    @Test func lossDropsOnASingleView() throws {
        let width = 64, height = 48
        let camera = frontCamera(width: width, height: height, focal: 50)
        let view = TrainingView(camera: camera, background: SplatTrainer.background)
        // Left half red, right half blue.
        let pixels = (0..<(width * height)).flatMap { index -> [UInt8] in index % width < width / 2 ? [220, 30, 30, 255] : [30, 30, 220, 255] }
        let target = TrainingImage(width: width, height: height, pixels: pixels)
        var generator = SeededGenerator(seed: 7)
        var params: [Float] = []
        for _ in 0..<200 {
            let z = Float.random(in: 2...4, using: &generator)
            let position = SIMD3(Float.random(in: -0.6...0.6, using: &generator) * z, Float.random(in: -0.45...0.45, using: &generator) * z, z)
            params += GaussianModel.gaussian(position: position, logScale: SIMD3(repeating: log(0.15)), color: SIMD3(repeating: 0.5), opacity: 0.3)
        }
        let session = try TrainingSession(model: GaussianModel(params: params), views: [view], images: [target], capacity: 200)
        let schedule = Schedule(iterations: 300, extent: 1)
        try session.run(viewIndex: 0, step: gradientsOnly)
        let initial = session.loss()
        for iteration in 1...300 { try session.run(viewIndex: 0, step: schedule.step(iteration)) }
        try session.run(viewIndex: 0, step: gradientsOnly)
        #expect(session.loss() < initial * 0.4, "loss \(initial) → \(session.loss())")
    }
}

struct TileBinnerTests {
    private func bin(rects: [SIMD4<UInt32>], depths: [Float], tilesX: Int, tiles: Int, capacity: Int) -> ([SIMD2<UInt32>], [UInt32]) {
        var ranges = [SIMD2<UInt32>](repeating: .zero, count: tiles)
        var list = [UInt32](repeating: .max, count: capacity)
        let binner = TileBinner()
        rects.withUnsafeBufferPointer { r in
            depths.withUnsafeBufferPointer { d in
                ranges.withUnsafeMutableBufferPointer { out in
                    list.withUnsafeMutableBufferPointer { l in
                        _ = binner.bin(count: rects.count, rects: r.baseAddress!, depths: d.baseAddress!, depthStride: 1,
                                       tilesX: tilesX, tileCount: tiles, ranges: out.baseAddress!, list: l.baseAddress!, capacity: capacity)
                    }
                }
            }
        }
        return (ranges, list)
    }

    @Test func listsEachTileFrontToBack() {
        let all = SIMD4<UInt32>(0, 0, 2, 1)
        let (ranges, list) = bin(rects: [all, all, SIMD4(1, 0, 2, 1), .zero], depths: [3, 1, 2, 0.5], tilesX: 2, tiles: 2, capacity: 16)
        #expect(ranges == [SIMD2(0, 2), SIMD2(2, 5)])
        #expect(Array(list[0..<2]) == [1, 0])
        #expect(Array(list[2..<5]) == [1, 2, 0])
    }

    @Test func dropsTheFarthestWhenFull() {
        let tile = SIMD4<UInt32>(0, 0, 1, 1)
        let (ranges, list) = bin(rects: [tile, tile, tile], depths: [3, 1, 2], tilesX: 1, tiles: 1, capacity: 2)
        #expect(ranges == [SIMD2(0, 2)])
        #expect(Array(list[0..<2]) == [1, 2])
    }
}

struct GaussianModelTests {
    @Test func densifyClonesSmallSplitsLargeAndPrunesTransparent() {
        var params = GaussianModel.gaussian(position: .zero, logScale: SIMD3(repeating: log(0.005)), color: SIMD3(repeating: 0.5), opacity: 0.5)
        params += GaussianModel.gaussian(position: SIMD3(1, 0, 0), logScale: SIMD3(repeating: log(0.1)), color: SIMD3(repeating: 0.5), opacity: 0.5)
        params += GaussianModel.gaussian(position: SIMD3(2, 0, 0), logScale: SIMD3(repeating: log(0.005)), color: SIMD3(repeating: 0.5), opacity: 0.002)
        var model = GaussianModel(params: params)
        var generator = SeededGenerator(seed: 1)
        let stats: [SIMD2<Float>] = [SIMD2(0.01, 10), SIMD2(0.01, 10), SIMD2(0, 10)]
        model.densify(stats: stats, extent: 1, rule: GaussianModel.DensifyRule(), generator: &generator)
        // Small kept + its clone, large replaced by two halves, transparent pruned.
        #expect(model.count == 4)
        let large = (0..<model.count).filter { simd_distance(model.position($0), SIMD3(1, 0, 0)) < 0.5 }
        #expect(large.count == 2)
        #expect(large.allSatisfy { abs(model.scale($0).x - 0.1 / 1.6) < 1e-4 })
        #expect(model.m.count == model.params.count)
    }

    @Test func densifyRespectsTheBudget() {
        let one = GaussianModel.gaussian(position: .zero, logScale: SIMD3(repeating: log(0.005)), color: SIMD3(repeating: 0.5), opacity: 0.5)
        var model = GaussianModel(params: one + one + one)
        var generator = SeededGenerator(seed: 1)
        var rule = GaussianModel.DensifyRule()
        rule.maxCount = 4
        model.densify(stats: [SIMD2(0.01, 1), SIMD2(0.02, 1), SIMD2(0.03, 1)], extent: 1, rule: rule, generator: &generator)
        #expect(model.count == 4)
    }

    @Test func spacingComesFromNeighbors() {
        let points = (0..<10).map { SIMD3<Float>(Float($0) * 0.1, 0, 0) }
        let spacing = GaussianModel.neighborSpacing(points, fallback: 0.2)
        #expect(abs(spacing[5] - (0.1 + 0.1 + 0.2) / 3) < 1e-4)
    }

    @Test func colorsAreSampledFromTheImages() {
        let view = TrainingView(camera: frontCamera(width: 16, height: 16, focal: 16), background: SplatTrainer.background)
        let colors = GaussianModel.sampleColors(points: [SIMD3(0, 0, 2), SIMD3(0, 0, -2)], views: [view],
                                                images: [solidImage(width: 16, height: 16, rgb: (255, 0, 0))])
        #expect(colors[0] == SIMD3(1, 0, 0))
        #expect(colors[1] == SIMD3(repeating: 0.5))
    }

    @Test func exportIsReadableBySplatScene() throws {
        var params = GaussianModel.gaussian(position: SIMD3(1, 2, 3), logScale: SIMD3(repeating: log(0.1)), color: SIMD3(0.9, 0.1, 0.5), opacity: 0.8)
        params += GaussianModel.gaussian(position: .zero, logScale: .zero, color: SIMD3(repeating: 0.5), opacity: 0.005)
        let scene = try SplatScene(data: GaussianModel(params: params).splatData())
        #expect(scene.count == 1)
        #expect(scene.splats[0].position.0 == 1)
        #expect(scene.splats[0].color & 0xff == 230)
    }
}

struct TrainedPathTests {
    @Test func posesAreLeveledAlongGravity() throws {
        // Looking along world −z with the sensor rolled 90° (phone held upright): image "down" is world +x.
        let c2w = simd_float4x4(SIMD4(0, 1, 0, 0), SIMD4(1, 0, 0, 0), SIMD4(0, 0, -1, 0), SIMD4(0, 1.5, 0, 1))
        let camera = CapturedCamera(fx: 700, fy: 700, cx: 479.5, cy: 359.5, width: 960, height: 720, cameraToWorld: c2w)
        let moved = CapturedCamera(fx: 700, fy: 700, cx: 479.5, cy: 359.5, width: 960, height: 720,
                                   cameraToWorld: simd_float4x4(c2w.columns.0, c2w.columns.1, c2w.columns.2, SIMD4(0, 1.5, -1, 1)))
        let path = try CameraPath(data: SplatTrainer.pathJSON(cameras: [camera, moved]))
        #expect(path.keyframes.count == 2)
        #expect(simd_distance(path.keyframes[0].up, SIMD3(0, 1, 0)) < 1e-5)
        #expect(simd_distance(path.keyframes[0].forward, SIMD3(0, 0, -1)) < 1e-5)
        #expect(abs(path.keyframes[0].fovY - 2 * atan(480 / 700)) < 1e-5)
    }
}

struct SplatTrainerTests {
    /// A tiny synthetic capture: 20 keyframes on an arc looking at a checkerboard wall.
    private static func writeCapture(to directory: URL) throws {
        let frames = directory.appending(path: "frames", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        var manifestFrames: [CaptureManifest.Frame] = []
        for index in 0..<CaptureManifest.minKeyframes {
            let name = String(format: "frame_%05d.jpg", index + 1)
            let image = try #require(MediaFixtures.image(width: 96, height: 72, offset: index))
            try SceneExporter.writeJPEG(image, to: frames.appending(path: name))
            var c2w = matrix_identity_float4x4
            c2w.columns.3 = SIMD4(Float(index) * 0.05 - 0.5, 0, 0, 1)
            manifestFrames.append(CaptureManifest.frame(image: name, camera: CapturedCamera(fx: 80, fy: 80, cx: 47.5, cy: 35.5, width: 96, height: 72, cameraToWorld: c2w)))
        }
        try CaptureManifest(frames: manifestFrames, pointCount: 0).encoded().write(to: directory.appending(path: "capture.json"))
        var cloud = PointCloudAccumulator()
        let points = (0..<300).map { SIMD3<Float>(Float($0 % 20) * 0.1 - 1, Float($0 / 20) * 0.1 - 0.7, 3) }
        cloud.add(identifiers: (0..<300).map(UInt64.init), positions: points)
        try cloud.encoded().write(to: directory.appending(path: "points.bin"))
    }

    @Test func trainsACaptureIntoFilesTheRendererReads() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "TrainerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.writeCapture(to: directory)
        let scene = try await SplatTrainer.run(directory: directory, options: SplatTrainer.Options(iterations: 120, imageLongSide: 96)) { _ in }
        #expect(scene.gaussians > 0)
        _ = try SplatScene(contentsOf: directory.appending(path: "scene.splat"))
        let path = try CameraPath(contentsOf: directory.appending(path: "path.json"))
        #expect(path.keyframes.count == CaptureManifest.minKeyframes)
    }

    @Test func rejectsAMissingCapture() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: "TrainerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        await #expect(throws: SplatTrainingError.invalidCapture) {
            _ = try await SplatTrainer.run(directory: directory, options: SplatTrainer.Options(iterations: 10)) { _ in }
        }
    }
}
