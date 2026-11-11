import ARKit
import Foundation
import Observation
import Walk3DKit

/// The camera side of the flow; `ARSceneCapture` in the app, a fake in tests.
@MainActor
public protocol SceneCapturing: AnyObject {
    /// World tracking is available (never in the simulator).
    var canCapture: Bool { get }
    /// For the camera preview.
    var session: ARSession { get }
    func start() throws(SceneCaptureError) -> AsyncStream<SceneCaptureStatus>
    func finish() async throws(SceneCaptureError) -> SceneCapture
    func cancel()
    /// Deletes every capture and the scenes trained from them.
    func purge()
}

extension ARSceneCapture: SceneCapturing {
    public var canCapture: Bool { ARSceneCapture.isSupported }
}

/// Walk 3D, all on the phone: record the rooms with ARKit → train the 3D → render the walk video.
@Observable
@MainActor
public final class Walk3DModel {
    public typealias Train = @Sendable (SceneCapture) -> AsyncThrowingStream<SplatTrainingEvent, any Error>
    public typealias Render = @Sendable (_ scene: TrainedScene, _ watermark: Bool) -> AsyncThrowingStream<Walk3DRenderEvent, any Error>

    public enum Phase: Equatable {
        case idle
        case capturing(SceneCaptureStatus)
        /// Saving the keyframes after the host taps "Concluir".
        case savingCapture
        case training(progress: Double, pausedForHeat: Bool)
        case rendering(progress: Double, pausedForHeat: Bool)
        case finished(Walk3DVideo)
        case failed(Failure)
    }

    public enum Failure: Equatable, Sendable {
        case unsupported
        case cameraDenied
        case captureTooShort
        /// The app left the screen while recording; ARKit may have lost its bearings.
        case captureInterrupted
        case insufficientStorage
        /// The GPU stopped because the app left the screen during training or rendering.
        case interrupted
        case overheated
        case failed
    }

    public private(set) var phase: Phase = .idle
    /// The free plan always carries the watermark; the server decides the plan.
    public let watermark: Bool

    private let capturer: any SceneCapturing
    private let train: Train
    private let render: Render
    private let requestCamera: @Sendable () async -> Bool
    private let keepAwake: @MainActor (Bool) -> Void
    /// Kept until a new recording starts, so a failed step can be retried without recording again.
    private var capture: SceneCapture?
    private var scene: TrainedScene?
    private var task: Task<Void, Never>?
    private var isStartingCapture = false

    public init(watermark: Bool, capturer: any SceneCapturing, train: @escaping Train, render: @escaping Render,
                requestCamera: @escaping @Sendable () async -> Bool, keepAwake: @escaping @MainActor (Bool) -> Void) {
        self.watermark = watermark
        self.capturer = capturer
        self.train = train
        self.render = render
        self.requestCamera = requestCamera
        self.keepAwake = keepAwake
    }

    public var isSupported: Bool { capturer.canCapture }
    public var previewSession: ARSession { capturer.session }

    public var isCapturing: Bool {
        if case .capturing = phase { true } else { false }
    }

    public var isWorking: Bool {
        if isStartingCapture { return true }
        switch phase {
        case .savingCapture, .training, .rendering: return true
        default: return false
        }
    }

    /// A failure after the recording was saved can resume from the saved files.
    public var canRetry: Bool {
        guard case .failed(let failure) = phase else { return false }
        return [.interrupted, .overheated, .failed].contains(failure) && (capture != nil || scene != nil)
    }

    // MARK: - Capture

    public func startCapture() {
        guard !isCapturing, !isWorking else { return }
        guard capturer.canCapture else {
            phase = .failed(.unsupported)
            return
        }
        // A new attempt never reuses a partial capture, trained scene, or previous render.
        discardFiles()
        isStartingCapture = true
        task = Task {
            defer { isStartingCapture = false }
            guard await requestCamera(), !Task.isCancelled else {
                if !Task.isCancelled { phase = .failed(.cameraDenied) }
                return
            }
            let statuses: AsyncStream<SceneCaptureStatus>
            do {
                statuses = try capturer.start()
            } catch {
                phase = .failed(Self.failure(error))
                return
            }
            phase = .capturing(SceneCaptureStatus(keyframes: 0, points: 0, tracking: .unavailable, isFull: false))
            for await status in statuses {
                guard isCapturing else { break }
                phase = .capturing(status)
                // The keyframe budget is spent: more walking would not be recorded.
                if status.isFull { finishCapture() }
            }
        }
    }

    public func finishCapture() {
        guard case .capturing(let status) = phase, status.canFinish else { return }
        phase = .savingCapture
        task?.cancel()
        task = Task {
            do {
                let capture = try await capturer.finish()
                self.capture = capture
                await process()
            } catch {
                phase = .failed(Self.failure(error))
            }
        }
    }

    public func cancelCapture() {
        guard isCapturing else { return }
        task?.cancel()
        capturer.cancel()
        discardFiles()
        phase = .idle
    }

    /// Recording cannot survive the app leaving the screen; training and rendering report it themselves.
    public func appDidLeaveForeground() {
        guard isCapturing || isStartingCapture else { return }
        task?.cancel()
        isStartingCapture = false
        if isCapturing { capturer.cancel() }
        discardFiles()
        phase = .failed(.captureInterrupted)
    }

    // MARK: - Processing

    public func retry() {
        guard canRetry else { return }
        // A remote scene is only a handle to a Mac job. Once that job failed,
        // retrying its render endpoint can never succeed. Discard the handle so
        // the retained ARKit capture is uploaded as a fresh job instead.
        if scene?.directory.path.hasPrefix("/remote-walk3d/") == true {
            scene = nil
        }
        task = Task { await process() }
    }

    public func cancelProcessing() {
        guard isWorking else { return }
        task?.cancel()
        keepAwake(false)
        discardFiles()
        phase = .idle
    }

    /// Stops the current flow and removes every temporary recording, scene, and render.
    public func restart() {
        task?.cancel()
        isStartingCapture = false
        if isCapturing { capturer.cancel() }
        keepAwake(false)
        discardFiles()
        phase = .idle
    }

    /// Sign-out: stops everything and deletes the recording and the 3D.
    public func reset() {
        restart()
    }

    /// Trains (unless a scene is already trained) and renders, keeping the screen on throughout.
    private func process() async {
        keepAwake(true)
        defer { keepAwake(false) }
        if scene == nil, let capture { await trainScene(capture) }
        guard let scene, !Task.isCancelled else { return }
        await renderVideo(scene)
    }

    private func trainScene(_ capture: SceneCapture) async {
        phase = .training(progress: 0, pausedForHeat: false)
        do {
            for try await event in train(capture) {
                switch event {
                case .progress(let value): phase = .training(progress: value, pausedForHeat: false)
                case .pausedForHeat:
                    if case .training(let progress, _) = phase { phase = .training(progress: progress, pausedForHeat: true) }
                case .finished(let scene): self.scene = scene
                }
            }
            if scene == nil, !Task.isCancelled {
                phase = .failed(.failed)
            }
        } catch {
            if !Task.isCancelled { phase = .failed(Self.failure(error)) }
        }
    }

    private func renderVideo(_ scene: TrainedScene) async {
        phase = .rendering(progress: 0, pausedForHeat: false)
        var didFinish = false
        do {
            for try await event in render(scene, watermark) {
                switch event {
                case .progress(let value): phase = .rendering(progress: value, pausedForHeat: false)
                case .pausedForHeat:
                    if case .rendering(let progress, _) = phase { phase = .rendering(progress: progress, pausedForHeat: true) }
                case .finished(let video):
                    didFinish = true
                    phase = .finished(video)
                }
            }
            if !didFinish, !Task.isCancelled {
                phase = .failed(.failed)
            }
        } catch {
            if !Task.isCancelled { phase = .failed(Self.failure(error)) }
        }
    }

    private func discardFiles() {
        capture = nil
        scene = nil
        capturer.purge()
    }

    static func failure(_ error: any Error) -> Failure {
        switch error {
        case SceneCaptureError.unsupported: .unsupported
        case SceneCaptureError.notEnoughKeyframes: .captureTooShort
        case SceneCaptureError.insufficientStorage: .insufficientStorage
        case SplatTrainingError.interrupted, Walk3DRenderError.gpuUnavailable: .interrupted
        case SplatTrainingError.overheated, Walk3DRenderError.overheated: .overheated
        default: .failed
        }
    }
}
