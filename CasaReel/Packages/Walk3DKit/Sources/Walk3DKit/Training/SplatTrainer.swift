import Foundation
import simd

/// The 3D scene trained from a capture, written next to it: `scene.splat` and `path.json`, the same files
/// the walk video renderer reads.
public struct TrainedScene: Sendable, Equatable {
    public let directory: URL
    public let gaussians: Int
}

public enum SplatTrainingEvent: Sendable, Equatable {
    /// 0–1.
    case progress(Double)
    case pausedForHeat
    case finished(TrainedScene)
}

public enum SplatTrainingError: Error, Sendable, Equatable {
    case invalidCapture
    case gpuUnavailable
    /// The GPU stopped mid-training, usually because the app left the foreground.
    case interrupted
    case overheated
    case writeFailed
    case cancelled
}

/// Trains Gaussian splats from an `ARSceneCapture` on the phone's GPU. No server, nothing leaves the device.
public struct SplatTrainer: Sendable {
    public struct Options: Sendable {
        /// About 5 000 steps reach most of the quality for a room; more mostly sharpens fine detail.
        public var iterations = 5_000
        /// Long side of the training images. 640 keeps the 240 keyframes near 300 MB of GPU memory.
        public var imageLongSide = 640
        public var maxGaussians = 300_000
        public var seed: UInt64 = 1

        public init(iterations: Int = 5_000, imageLongSide: Int = 640, maxGaussians: Int = 300_000, seed: UInt64 = 1) {
            self.iterations = iterations
            self.imageLongSide = imageLongSide
            self.maxGaussians = maxGaussians
            self.seed = seed
        }
    }

    /// Must match `SplatRenderer.background`, so what training learns is what the video shows.
    static let background = SIMD3<Float>(0.05, 0.05, 0.06)

    public init() {}

    public func train(capture: SceneCapture, options: Options = Options()) -> AsyncThrowingStream<SplatTrainingEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let scene = try await Self.run(directory: capture.directory, options: options) { continuation.yield($0) }
                    continuation.yield(.finished(scene))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? SplatTrainingError.cancelled : error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Pipeline

    static func run(directory: URL, options: Options, onEvent: @Sendable (SplatTrainingEvent) -> Void) async throws -> TrainedScene {
        let (cameras, points) = try loadCapture(directory)
        onEvent(.progress(0.01))
        let size = cameras[0].0
        let factor = min(1, Float(options.imageLongSide) / Float(max(size.width, size.height)))
        let width = Int((Float(size.width) * factor).rounded()), height = Int((Float(size.height) * factor).rounded())
        var views: [TrainingView] = [], images: [TrainingImage] = []
        for (camera, url) in cameras {
            try Task.checkCancellation()
            guard let image = TrainingImage(contentsOf: url, width: width, height: height) else { continue }
            views.append(TrainingView(camera: camera.scaled(by: Float(width) / Float(camera.width), width: width, height: height),
                                      background: background))
            images.append(image)
        }
        guard views.count >= CaptureManifest.minKeyframes else { throw SplatTrainingError.invalidCapture }
        onEvent(.progress(0.03))

        var generator = SeededGenerator(seed: options.seed)
        let extent = GaussianModel.extent(of: views)
        let initial = GaussianModel.initial(points: points, views: views, images: images, extent: extent, generator: &generator)
        let session: TrainingSession
        do {
            session = try TrainingSession(model: initial, views: views, images: images, capacity: options.maxGaussians)
        } catch {
            throw SplatTrainingError.gpuUnavailable
        }
        images.removeAll()
        onEvent(.progress(0.05))

        let schedule = Schedule(iterations: options.iterations, extent: extent)
        var order: [Int] = []
        for iteration in 1...options.iterations {
            if order.isEmpty { order = Array(views.indices).shuffled(using: &generator) }
            let viewIndex = order.removeLast()
            do {
                try session.run(viewIndex: viewIndex, step: schedule.step(iteration))
            } catch {
                throw SplatTrainingError.interrupted
            }
            if schedule.densifies(after: iteration) {
                var model = session.download()
                model.densify(stats: session.densifyStatistics(), extent: extent,
                              rule: schedule.rule(iteration, maxCount: options.maxGaussians), generator: &generator)
                if schedule.resetsOpacity(after: iteration) { model.resetOpacity() }
                session.upload(model)
            }
            if iteration.isMultiple(of: 25) {
                try Task.checkCancellation()
                try await coolDown(onEvent: onEvent)
                onEvent(.progress(0.05 + 0.9 * Double(iteration) / Double(options.iterations)))
            }
        }
        let model = session.download()
        let scene = try write(model: model, cameras: cameras.map(\.0), to: directory)
        onEvent(.progress(1))
        return scene
    }

    static func loadCapture(_ directory: URL) throws -> ([(CapturedCamera, URL)], [SIMD3<Float>]) {
        guard let data = try? Data(contentsOf: directory.appending(path: "capture.json")),
              let manifest = try? CaptureManifest.load(from: data),
              let pointData = try? Data(contentsOf: directory.appending(path: "points.bin")),
              let points = try? PointCloudAccumulator.decode(pointData)
        else { throw SplatTrainingError.invalidCapture }
        let cameras = manifest.frames.map { ($0.camera, directory.appending(path: "frames/\($0.image)")) }
        // One video format per ARKit session; a frame of another size would not fit the texture array.
        let size = (cameras[0].0.width, cameras[0].0.height)
        let matching = cameras.filter { ($0.0.width, $0.0.height) == size }
        guard matching.count >= CaptureManifest.minKeyframes else { throw SplatTrainingError.invalidCapture }
        return (matching, points)
    }

    /// Waits while the phone is hot; gives up when it is critical or stays hot for two minutes.
    private static func coolDown(onEvent: @Sendable (SplatTrainingEvent) -> Void) async throws {
        var waited = 0
        while ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
            if ProcessInfo.processInfo.thermalState == .critical || waited >= 120 { throw SplatTrainingError.overheated }
            if waited == 0 { onEvent(.pausedForHeat) }
            try await Task.sleep(for: .seconds(1))
            waited += 1
        }
    }

    // MARK: - Output

    static func write(model: GaussianModel, cameras: [CapturedCamera], to directory: URL) throws -> TrainedScene {
        let splats = model.splatData()
        guard !splats.isEmpty else { throw SplatTrainingError.writeFailed }
        do {
            try splats.write(to: directory.appending(path: "scene.splat"), options: .completeFileProtectionUnlessOpen)
            try pathJSON(cameras: cameras).write(to: directory.appending(path: "path.json"), options: .completeFileProtectionUnlessOpen)
        } catch {
            throw SplatTrainingError.writeFailed
        }
        return TrainedScene(directory: directory, gaussians: splats.count / SplatScene.recordSize)
    }

    /// `path.json` in the format `CameraPath` reads. Keyframes are landscape sensor images while the host
    /// holds the phone upright, so each pose is re-rolled to keep image "down" along gravity (ARKit's −y),
    /// and the video's vertical field of view is the sensor's horizontal one.
    static func pathJSON(cameras: [CapturedCamera]) throws -> Data {
        let gravityDown = SIMD3<Float>(0, -1, 0)
        let frames: [[String: Any]] = cameras.enumerated().map { index, camera in
            let forward = camera.forward
            var down = gravityDown - simd_dot(gravityDown, forward) * forward
            if simd_length(down) < 1e-3 {
                let column = camera.cameraToWorld.columns.1
                down = SIMD3(column.x, column.y, column.z)
            }
            down = simd_normalize(down)
            let right = simd_cross(down, forward)
            let rotation = (0..<3).map { [right[$0], down[$0], forward[$0]] }
            let position = camera.position
            return [
                "image": String(format: "capture/frame_%05d.jpg", index + 1),
                "position": [position.x, position.y, position.z],
                "rotation": rotation,
                "fov_y": 2 * atan(Float(camera.width) / (2 * camera.fx)),
                "aspect": Float(camera.height) / Float(camera.width),
            ]
        }
        let path: [String: Any] = [
            "format": "casareel-walk3d-path", "version": 1, "coordinates": "arkit_gravity_opencv_camera_to_world",
            "segments": [["name": "capture", "frames": frames]], "photos": [],
        ]
        return try JSONSerialization.data(withJSONObject: path, options: [.sortedKeys])
    }
}

/// Learning rates and densification timing, compressed from the paper's 30 000-step schedule.
struct Schedule {
    let iterations: Int
    let extent: Float

    var densifyFrom: Int { min(500, iterations / 10) }
    var densifyUntil: Int { iterations / 2 }
    var densifyInterval: Int { 100 }
    /// One opacity reset on long enough runs, early enough to recover before densification ends.
    var opacityReset: Int? { iterations >= 3_000 ? Int(Double(iterations) * 0.3) : nil }

    func step(_ iteration: Int) -> TrainingSession.Step {
        let t = Float(iteration - 1) / Float(max(iterations - 1, 1))
        let position = exp(log(1.6e-4) * (1 - t) + log(1.6e-6) * t) * extent
        return TrainingSession.Step(
            lrA: SIMD4(position, 0.005, 0.001, 0.005),
            lrB: SIMD4(0.05, 1 - pow(0.9, Float(iteration)), 1 - pow(0.999, Float(iteration)), 1),
            counts: .zero
        )
    }

    func densifies(after iteration: Int) -> Bool {
        iteration >= densifyFrom && iteration <= densifyUntil && iteration.isMultiple(of: densifyInterval)
    }

    func resetsOpacity(after iteration: Int) -> Bool {
        opacityReset.map { iteration == ($0 / densifyInterval) * densifyInterval } ?? false
    }

    func rule(_ iteration: Int, maxCount: Int) -> GaussianModel.DensifyRule {
        var rule = GaussianModel.DensifyRule()
        rule.maxCount = maxCount
        rule.pruneLarge = opacityReset.map { iteration > $0 } ?? false
        return rule
    }
}
