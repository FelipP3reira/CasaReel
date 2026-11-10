import ARKit
import Foundation
import Testing
import Walk3DKit
@testable import FeatureWalk3D

@MainActor
private final class FakeCapturer: SceneCapturing {
    var canCapture = true
    let session = ARSession()
    var finishResult: Result<SceneCapture, SceneCaptureError> = .success(SceneCapture(directory: URL(fileURLWithPath: "/tmp/capture"), keyframes: 30))
    private(set) var cancelled = 0
    private(set) var purged = 0
    private(set) var starts = 0
    private var continuation: AsyncStream<SceneCaptureStatus>.Continuation?

    func start() throws(SceneCaptureError) -> AsyncStream<SceneCaptureStatus> {
        starts += 1
        let (stream, continuation) = AsyncStream.makeStream(of: SceneCaptureStatus.self)
        self.continuation = continuation
        return stream
    }

    func send(keyframes: Int, tracking: SceneCaptureStatus.Tracking = .normal, isFull: Bool = false) {
        continuation?.yield(SceneCaptureStatus(keyframes: keyframes, points: 100, tracking: tracking, isFull: isFull))
    }

    func finish() async throws(SceneCaptureError) -> SceneCapture { try finishResult.get() }
    func cancel() { cancelled += 1 }
    func purge() { purged += 1 }
}

/// Records calls made from `@Sendable` closures.
private final class Log<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Value] = []
    var values: [Value] { lock.withLock { stored } }
    func record(_ value: Value) { lock.withLock { stored.append(value) } }
}

@MainActor
struct Walk3DModelTests {
    private nonisolated static let scene = TrainedScene(directory: URL(fileURLWithPath: "/tmp/capture"), gaussians: 1_000)
    private nonisolated static let video = Walk3DVideo(fileURL: URL(fileURLWithPath: "/tmp/w.mp4"), durationMs: 12_000)

    private nonisolated static func trainOK(_: SceneCapture) -> AsyncThrowingStream<SplatTrainingEvent, any Error> {
        AsyncThrowingStream { $0.yield(.progress(0.5)); $0.yield(.pausedForHeat); $0.yield(.finished(scene)); $0.finish() }
    }

    private nonisolated static func renderOK(_: TrainedScene, _: Bool) -> AsyncThrowingStream<Walk3DRenderEvent, any Error> {
        AsyncThrowingStream { $0.yield(.progress(0.5)); $0.yield(.finished(video)); $0.finish() }
    }

    private func makeModel(
        capturer: FakeCapturer = FakeCapturer(),
        camera: Bool = true,
        train: @escaping Walk3DModel.Train = trainOK,
        render: @escaping Walk3DModel.Render = renderOK,
        awake: Log<Bool> = Log()
    ) -> Walk3DModel {
        Walk3DModel(watermark: true, capturer: capturer, train: train, render: render,
                    requestCamera: { camera }, keepAwake: { awake.record($0) })
    }

    private func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    private func startCapturing(_ model: Walk3DModel) async {
        model.startCapture()
        await settle { model.isCapturing }
    }

    @Test func recordsTrainsAndRendersInOneGo() async {
        let capturer = FakeCapturer()
        let awake = Log<Bool>()
        let watermarks = Log<Bool>()
        let model = makeModel(capturer: capturer, render: { scene, watermark in
            watermarks.record(watermark)
            return Self.renderOK(scene, watermark)
        }, awake: awake)
        await startCapturing(model)
        #expect(capturer.purged == 1, "a new recording drops the previous one")
        capturer.send(keyframes: 25)
        await settle { model.phase == .capturing(SceneCaptureStatus(keyframes: 25, points: 100, tracking: .normal, isFull: false)) }
        model.finishCapture()
        await settle { if case .finished = model.phase { true } else { false } }
        #expect(model.phase == .finished(Self.video))
        #expect(watermarks.values == [true])
        #expect(awake.values == [true, false], "screen kept on from training to the end of the render")
    }

    @Test func finishingNeedsEnoughKeyframes() async {
        let capturer = FakeCapturer()
        let model = makeModel(capturer: capturer)
        await startCapturing(model)
        capturer.send(keyframes: 5)
        await settle { if case .capturing(let status) = model.phase { status.keyframes == 5 } else { false } }
        model.finishCapture()
        #expect(model.isCapturing)
    }

    @Test func aFullBudgetFinishesByItself() async {
        let capturer = FakeCapturer()
        let model = makeModel(capturer: capturer)
        await startCapturing(model)
        capturer.send(keyframes: SceneCaptureStatus.maxKeyframes, isFull: true)
        await settle { if case .finished = model.phase { true } else { false } }
        #expect(model.phase == .finished(Self.video))
    }

    @Test func leavingTheScreenWhileRecordingCancelsIt() async {
        let capturer = FakeCapturer()
        let model = makeModel(capturer: capturer)
        await startCapturing(model)
        model.appDidLeaveForeground()
        #expect(model.phase == .failed(.captureInterrupted))
        #expect(capturer.cancelled == 1)
        #expect(!model.canRetry, "there is no saved recording to resume from")
    }

    @Test func cameraDeniedAndUnsupportedDevicesAreExplained() async {
        let denied = makeModel(camera: false)
        denied.startCapture()
        await settle { denied.phase != .idle }
        #expect(denied.phase == .failed(.cameraDenied))

        let capturer = FakeCapturer()
        capturer.canCapture = false
        let unsupported = makeModel(capturer: capturer)
        unsupported.startCapture()
        #expect(unsupported.phase == .failed(.unsupported))
    }

    @Test func deniedCameraPermissionDoesNotStartOrDuplicateTheFlow() async {
        let capturer = FakeCapturer()
        let requests = Log<Int>()
        let model = Walk3DModel(
            watermark: true,
            capturer: capturer,
            train: Self.trainOK,
            render: Self.renderOK,
            requestCamera: {
                requests.record(1)
                return false
            },
            keepAwake: { _ in }
        )

        #expect(requests.values.isEmpty, "camera access is requested only after the user starts recording")
        model.startCapture()
        model.startCapture()
        await settle { model.phase == .failed(.cameraDenied) }

        #expect(requests.values == [1])
        #expect(capturer.starts == 0)
    }

    @Test func aShortRecordingIsReported() async {
        let capturer = FakeCapturer()
        capturer.finishResult = .failure(.notEnoughKeyframes(found: 12))
        let model = makeModel(capturer: capturer)
        await startCapturing(model)
        capturer.send(keyframes: 25)
        await settle { if case .capturing(let status) = model.phase { status.canFinish } else { false } }
        model.finishCapture()
        await settle { if case .failed = model.phase { true } else { false } }
        #expect(model.phase == .failed(.captureTooShort))
    }

    @Test func anInterruptedTrainingResumesFromTheSavedRecording() async {
        let capturer = FakeCapturer()
        let attempts = Log<Int>()
        let model = makeModel(capturer: capturer, train: { capture in
            attempts.record(capture.keyframes)
            if attempts.values.count == 1 { return AsyncThrowingStream { $0.finish(throwing: SplatTrainingError.interrupted) } }
            return Self.trainOK(capture)
        })
        await startCapturing(model)
        capturer.send(keyframes: 30)
        await settle { if case .capturing(let status) = model.phase { status.canFinish } else { false } }
        model.finishCapture()
        await settle { if case .failed = model.phase { true } else { false } }
        #expect(model.phase == .failed(.interrupted))
        #expect(model.canRetry)
        model.retry()
        await settle { if case .finished = model.phase { true } else { false } }
        #expect(model.phase == .finished(Self.video))
        #expect(attempts.values == [30, 30], "the same recording, not a new one")
    }

    @Test func aFailedRenderRetriesWithoutTrainingAgain() async {
        let capturer = FakeCapturer()
        let trainings = Log<Int>()
        let renders = Log<Int>()
        let model = makeModel(capturer: capturer, train: { capture in
            trainings.record(1)
            return Self.trainOK(capture)
        }, render: { scene, watermark in
            renders.record(1)
            if renders.values.count == 1 { return AsyncThrowingStream { $0.finish(throwing: Walk3DRenderError.overheated) } }
            return Self.renderOK(scene, watermark)
        })
        await startCapturing(model)
        capturer.send(keyframes: 30)
        await settle { if case .capturing(let status) = model.phase { status.canFinish } else { false } }
        model.finishCapture()
        await settle { if case .failed = model.phase { true } else { false } }
        #expect(model.phase == .failed(.overheated))
        model.retry()
        await settle { if case .finished = model.phase { true } else { false } }
        #expect(trainings.values.count == 1)
        #expect(renders.values.count == 2)
    }

    @Test func cancellingProcessingStopsAndReleasesTheScreen() async {
        let capturer = FakeCapturer()
        let awake = Log<Bool>()
        let model = makeModel(capturer: capturer, train: { _ in AsyncThrowingStream { $0.yield(.progress(0.1)) } }, awake: awake)
        await startCapturing(model)
        capturer.send(keyframes: 30)
        await settle { if case .capturing(let status) = model.phase { status.canFinish } else { false } }
        model.finishCapture()
        await settle { if case .training(let progress, _) = model.phase { progress > 0 } else { false } }
        model.cancelProcessing()
        #expect(model.phase == .idle)
        #expect(awake.values.last == false)
    }

    @Test func endingTrainingWithoutASceneReportsFailure() async {
        let capturer = FakeCapturer()
        let model = makeModel(
            capturer: capturer,
            train: { _ in AsyncThrowingStream { $0.finish() } }
        )

        await startCapturing(model)
        capturer.send(keyframes: 30)
        await settle { if case .capturing(let status) = model.phase { status.canFinish } else { false } }
        model.finishCapture()
        await settle { model.phase == .failed(.failed) }

        #expect(model.canRetry)
    }

    @Test func endingRenderingWithoutAVideoReportsFailure() async {
        let capturer = FakeCapturer()
        let model = makeModel(
            capturer: capturer,
            render: { _, _ in AsyncThrowingStream { $0.finish() } }
        )

        await startCapturing(model)
        capturer.send(keyframes: 30)
        await settle { if case .capturing(let status) = model.phase { status.canFinish } else { false } }
        model.finishCapture()
        await settle { model.phase == .failed(.failed) }

        #expect(model.canRetry)
    }

    @Test func cancellingRecordingPurgesTemporaryFiles() async {
        let capturer = FakeCapturer()
        let model = makeModel(capturer: capturer)

        await startCapturing(model)
        model.cancelCapture()

        #expect(model.phase == .idle)
        #expect(capturer.cancelled == 1)
        #expect(capturer.purged == 2)
    }

    @Test func resetDeletesTheRecording() async {
        let capturer = FakeCapturer()
        let model = makeModel(capturer: capturer)
        await startCapturing(model)
        model.reset()
        #expect(model.phase == .idle)
        #expect(capturer.cancelled == 1)
        #expect(capturer.purged == 2)
    }
}

@MainActor
struct CaptureHintTests {
    @Test func hintsFollowTracking() {
        let limited = SceneCaptureStatus(keyframes: 3, points: 0, tracking: .limited, isFull: false)
        #expect(CaptureView.symbol(for: limited) == "exclamationmark.triangle.fill")
        let ready = SceneCaptureStatus(keyframes: SceneCaptureStatus.minKeyframes, points: 0, tracking: .normal, isFull: false)
        #expect(CaptureView.symbol(for: ready) == "checkmark.circle.fill")
    }
}
