@preconcurrency import ARKit
import CoreImage
import Foundation
import os

/// What the capture screen shows while the host walks.
public struct SceneCaptureStatus: Sendable, Equatable {
    public enum Tracking: Sendable, Equatable {
        case normal
        /// Moving too fast, too dark or not enough texture: keyframes pause until tracking recovers.
        case limited
        case unavailable
    }

    public var keyframes: Int
    public var points: Int
    public var tracking: Tracking
    public var isFull: Bool

    public var canFinish: Bool { keyframes >= CaptureManifest.minKeyframes }
}

/// A finished capture on disk: `capture.json`, `points.bin` and `frames/`.
public struct SceneCapture: Sendable, Equatable {
    public let directory: URL
    public let keyframes: Int
}

/// Records a room walk with ARKit world tracking (no LiDAR needed): keyframe images plus the camera
/// pose ARKit tracked for each, so no structure-from-motion is needed afterwards.
///
/// Frames never leave the device and are re-encoded from pixels (no EXIF, no GPS).
@MainActor
public final class ARSceneCapture {
    public static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    /// For the camera preview.
    public let session = ARSession()
    private let recorder: CaptureRecorder
    private let workDirectory: URL

    public init(workDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "CasaReelWalk3DCapture", directoryHint: .isDirectory)) {
        self.workDirectory = workDirectory
        recorder = CaptureRecorder()
    }

    /// Starts tracking and recording; the stream reports progress until `finish()` or `cancel()`.
    public func start() throws(SceneCaptureError) -> AsyncStream<SceneCaptureStatus> {
        guard Self.isSupported else { throw .unsupported }
        let job = workDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try Self.ensureFreeSpace()
        do {
            try FileManager.default.createDirectory(at: job.appending(path: "frames", directoryHint: .isDirectory), withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
        } catch {
            throw .writeFailed
        }
        let (stream, continuation) = AsyncStream.makeStream(of: SceneCaptureStatus.self, bufferingPolicy: .bufferingNewest(1))
        recorder.begin(directory: job, continuation: continuation)
        session.delegate = recorder
        session.delegateQueue = recorder.queue
        session.run(Self.configuration(), options: [.resetTracking, .removeExistingAnchors])
        return stream
    }

    /// Stops the camera and writes the manifest. The capture is deleted if it is too short.
    public func finish() async throws(SceneCaptureError) -> SceneCapture {
        session.pause()
        let recorder = recorder
        let result = await withCheckedContinuation { continuation in
            recorder.queue.async { continuation.resume(returning: recorder.finish()) }
        }
        return try result.get()
    }

    /// Stops the camera and deletes everything recorded.
    public func cancel() {
        session.pause()
        let recorder = recorder
        recorder.queue.async { recorder.discard() }
    }

    public func purge() {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    private static func configuration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        // Gravity-aligned world (y up), so the walk video can level its horizon.
        configuration.worldAlignment = .gravity
        configuration.isAutoFocusEnabled = true
        configuration.planeDetection = []
        configuration.environmentTexturing = .none
        return configuration
    }

    /// Keyframes, training buffers and the rendered video: about 500 MB with margin.
    private static func ensureFreeSpace() throws(SceneCaptureError) {
        let values = try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values?.volumeAvailableCapacityForImportantUsage, available < 500_000_000 {
            throw .insufficientStorage
        }
    }
}

/// The ARSession delegate. All of its state is touched only on `queue` (ARKit's delegate queue and the
/// blocks `ARSceneCapture` sends there), which is what makes the `@unchecked Sendable` sound.
final class CaptureRecorder: NSObject, ARSessionDelegate, @unchecked Sendable {
    /// Long side of a training image. Full sensor frames would multiply training time and memory on the
    /// phone for detail the walk video (1080 px wide, rotated) barely shows.
    static let imageLongSide = 960

    let queue = DispatchQueue(label: "br.com.casareel.walk3d.capture", qos: .userInitiated)
    private let log = Logger(subsystem: "br.com.casareel.app", category: "Walk3DCapture")
    private let context = CIContext(options: [.cacheIntermediates: false])

    private var directory: URL?
    private var continuation: AsyncStream<SceneCaptureStatus>.Continuation?
    private var selector = KeyframeSelector()
    private var points = PointCloudAccumulator()
    private var frames: [CaptureManifest.Frame] = []
    private var lastPointUpdate: TimeInterval = 0
    private var writeFailed = false

    func begin(directory: URL, continuation: AsyncStream<SceneCaptureStatus>.Continuation) {
        queue.async { [self] in
            discard()
            self.directory = directory
            self.continuation = continuation
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let directory, !writeFailed else { return }
        let tracking = Self.tracking(frame.camera.trackingState)
        if tracking == .normal {
            addPoints(of: frame)
            let camera = CapturedCamera(arkit: frame.camera)
            if selector.keep(time: frame.timestamp, position: camera.position, forward: camera.forward) {
                save(frame.capturedImage, camera: camera, in: directory)
            }
        }
        continuation?.yield(SceneCaptureStatus(keyframes: frames.count, points: points.points.count, tracking: tracking, isFull: selector.isFull))
    }

    func session(_ session: ARSession, didFailWithError error: any Error) {
        log.error("AR session failed: \(error.localizedDescription, privacy: .private)")
        continuation?.yield(SceneCaptureStatus(keyframes: frames.count, points: points.points.count, tracking: .unavailable, isFull: selector.isFull))
    }

    func finish() -> Result<SceneCapture, SceneCaptureError> {
        defer { reset() }
        guard let directory else { return .failure(.invalidCapture) }
        guard !writeFailed else {
            try? FileManager.default.removeItem(at: directory)
            return .failure(.writeFailed)
        }
        guard frames.count >= CaptureManifest.minKeyframes else {
            try? FileManager.default.removeItem(at: directory)
            return .failure(.notEnoughKeyframes(found: frames.count))
        }
        do {
            let manifest = try CaptureManifest(frames: frames, pointCount: points.points.count).encoded()
            try manifest.write(to: directory.appending(path: "capture.json"), options: .completeFileProtectionUnlessOpen)
            try points.encoded().write(to: directory.appending(path: "points.bin"), options: .completeFileProtectionUnlessOpen)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            return .failure(.writeFailed)
        }
        return .success(SceneCapture(directory: directory, keyframes: frames.count))
    }

    func discard() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        reset()
    }

    private func reset() {
        continuation?.finish()
        continuation = nil
        directory = nil
        selector = KeyframeSelector()
        points = PointCloudAccumulator()
        frames = []
        lastPointUpdate = 0
        writeFailed = false
    }

    /// ARKit refines points over time; merging a few times per second is plenty.
    private func addPoints(of frame: ARFrame) {
        guard frame.timestamp - lastPointUpdate >= 0.25, let cloud = frame.rawFeaturePoints else { return }
        lastPointUpdate = frame.timestamp
        points.add(identifiers: cloud.identifiers, positions: cloud.points)
    }

    private func save(_ pixelBuffer: CVPixelBuffer, camera: CapturedCamera, in directory: URL) {
        let factor = Float(Self.imageLongSide) / Float(max(camera.width, camera.height))
        let width = Int((Float(camera.width) * factor).rounded()), height = Int((Float(camera.height) * factor).rounded())
        let image = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: CGAffineTransform(scaleX: CGFloat(factor), y: CGFloat(factor)))
        let name = String(format: "frame_%05d.jpg", frames.count + 1)
        guard let cgImage = context.createCGImage(image, from: CGRect(x: 0, y: 0, width: width, height: height)) else {
            writeFailed = true
            return
        }
        do {
            try SceneExporter.writeJPEG(cgImage, to: directory.appending(path: "frames/\(name)"))
        } catch {
            writeFailed = true
            return
        }
        frames.append(CaptureManifest.frame(image: name, camera: camera.scaled(by: factor, width: width, height: height)))
    }

    private static func tracking(_ state: ARCamera.TrackingState) -> SceneCaptureStatus.Tracking {
        switch state {
        case .normal: .normal
        case .limited: .limited
        case .notAvailable: .unavailable
        }
    }
}

extension CapturedCamera {
    /// Intrinsics and image size are in the sensor's landscape orientation, as `capturedImage` is.
    init(arkit camera: ARCamera) {
        let k = camera.intrinsics
        self.init(fx: k[0][0], fy: k[1][1], cx: k[2][0], cy: k[2][1],
                  width: Int(camera.imageResolution.width), height: Int(camera.imageResolution.height),
                  cameraToWorld: Self.openCVCameraToWorld(arkit: camera.transform))
    }
}
