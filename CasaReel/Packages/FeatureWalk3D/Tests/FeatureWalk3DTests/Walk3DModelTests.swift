import Foundation
import Testing
import Walk3DKit
@testable import FeatureWalk3D

@MainActor
struct Walk3DModelTests {
    private nonisolated static let archive = URL(fileURLWithPath: "/tmp/scene.aar")

    private func model(
        export: @escaping Walk3DModel.Export = { _, _ in
            AsyncThrowingStream { $0.yield(.progress(0.5)); $0.yield(.finished(SceneExportResult(archiveURL: archive, photoCount: 3, frameCount: 40))); $0.finish() }
        },
        render: @escaping Walk3DModel.Render = { _, _ in AsyncThrowingStream { $0.finish() } }
    ) -> Walk3DModel {
        Walk3DModel(watermark: true, export: export, render: render)
    }

    private func settle(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func exportNeedsMediaAndReportsTheResult() async {
        let model = model()
        #expect(!model.canExport)
        model.setMedia(photos: [URL(fileURLWithPath: "/tmp/a.jpg")], videos: [URL(fileURLWithPath: "/tmp/b.mov")])
        #expect(model.media == .ready(photos: 1, videos: 1))
        #expect(model.canExport)
        model.exportScene()
        await settle { if case .exported = model.exportState { true } else { false } }
        #expect(model.exportState == .exported(SceneExportResult(archiveURL: Self.archive, photoCount: 3, frameCount: 40)))
    }

    @Test func exportErrorsAreShown() async {
        let model = model(export: { _, _ in AsyncThrowingStream { $0.finish(throwing: SceneExportError.notEnoughImages(found: 4)) } })
        model.setMedia(photos: [URL(fileURLWithPath: "/tmp/a.jpg")], videos: [])
        model.exportScene()
        await settle { if case .failed = model.exportState { true } else { false } }
        #expect(model.exportState == .failed(.notEnoughImages(found: 4)))
    }

    @Test func loadingSortsPhotosAndVideosAndFailsWhenNothingLoads() async {
        let model = model()
        model.loadMedia(count: 3) { index in
            index == 1 ? .video(URL(fileURLWithPath: "/tmp/v.mov")) : index == 0 ? .photo(URL(fileURLWithPath: "/tmp/p.jpg")) : nil
        }
        await settle { model.media != .loading }
        #expect(model.media == .ready(photos: 1, videos: 1))
        model.loadMedia(count: 2) { _ in nil }
        await settle { model.media != .loading }
        #expect(model.media == .failed)
    }

    @Test func renderPassesTheWatermarkAndFinishes() async throws {
        let package = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).aar")
        try Data("x".utf8).write(to: package)
        defer { try? FileManager.default.removeItem(at: package) }
        let video = Walk3DVideo(fileURL: URL(fileURLWithPath: "/tmp/w.mp4"), durationMs: 12_000)
        let watermarks = WatermarkLog()
        let model = model(render: { _, watermark in
            watermarks.record(watermark)
            return AsyncThrowingStream { $0.yield(.pausedForHeat); $0.yield(.finished(video)); $0.finish() }
        })
        model.renderPackage(at: package)
        await settle { if case .finished = model.renderState { true } else { false } }
        #expect(model.renderState == .finished(video))
        #expect(watermarks.values == [true])
    }

    @Test func unreadablePackageFailsImmediately() {
        let model = model()
        model.renderPackage(at: URL(fileURLWithPath: "/nonexistent/scene.aar"))
        #expect(model.renderState == .failed(.invalidPackage(.invalidPackage)))
    }
}

private final class WatermarkLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Bool] = []
    var values: [Bool] { lock.withLock { stored } }
    func record(_ value: Bool) { lock.withLock { stored.append(value) } }
}
