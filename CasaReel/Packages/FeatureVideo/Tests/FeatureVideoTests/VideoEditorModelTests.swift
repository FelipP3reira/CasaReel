import CoreGraphics
import Domain
import Foundation
import os
import Testing
@testable import FeatureVideo

func slug(_ raw: String) -> TemplateSlug {
    guard let slug = TemplateSlug(rawValue: raw) else { preconditionFailure("invalid test slug") }
    return slug
}

final class FakeRenderer: VideoRenderer {
    let templates: [VideoTemplateInfo]
    private let state = OSAllocatedUnfairLock(initialState: (requests: [VideoRenderRequest](), discarded: [URL]()))
    private let failWith: RenderError?
    private let steps: Int

    init(templates: [VideoTemplateInfo], failWith: RenderError? = nil, steps: Int = 3) {
        self.templates = templates
        self.failWith = failWith
        self.steps = steps
    }

    var requests: [VideoRenderRequest] { state.withLock { $0.requests } }
    var discarded: [URL] { state.withLock { $0.discarded } }

    func render(_ request: VideoRenderRequest) -> AsyncThrowingStream<RenderEvent, any Error> {
        state.withLock { $0.requests.append(request) }
        let failWith = failWith, steps = steps
        return AsyncThrowingStream { continuation in
            let task = Task {
                for step in 0..<steps {
                    try? await Task.sleep(for: .milliseconds(20))
                    if Task.isCancelled { continuation.finish(throwing: RenderError.cancelled); return }
                    continuation.yield(.progress(Double(step) / Double(steps)))
                    if step == 1 { continuation.yield(.pausedForHeat) }
                }
                if let failWith { continuation.finish(throwing: failWith); return }
                let url = URL(filePath: "/tmp/\(request.aspect == .vertical ? "v" : "h")-\(request.quality == .preview ? "preview" : "final").mp4")
                continuation.yield(.finished(RenderedVideo(
                    fileURL: url, thumbnailURL: url, templateSlug: request.templateSlug, templateVersion: 1, aspect: request.aspect,
                    durationMs: 1_000, sizeBytes: 1, sha256: "x", watermark: request.watermark
                )))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func discard(_ video: RenderedVideo) {
        state.withLock { $0.discarded.append(video.fileURL) }
    }
}

actor FakeDrafts: VideoDraftStoring {
    private(set) var saved: VideoDraft?
    private(set) var saves = 0
    private(set) var deletes = 0

    func load() async -> VideoDraft? { saved }
    func save(_ draft: VideoDraft) async { saved = draft; saves += 1 }
    func delete() async { saved = nil; deletes += 1 }
}

struct FakePower: PowerStatusProviding {
    var low = false
    @MainActor var shouldWarn: Bool { low }
}

@MainActor
struct VideoEditorModelTests {
    private let classic = VideoTemplateInfo(slug: slug("classic-clean"), version: 1, aspects: [.vertical, .horizontal], sceneCount: 2)
    private let social = VideoTemplateInfo(slug: slug("dynamic-social"), version: 1, aspects: [.vertical], sceneCount: 3)
    private let premium = VideoTemplateInfo(slug: slug("luxury-gold"), version: 1, aspects: [.horizontal], sceneCount: 2)

    private func photo(_ name: String) -> PreparedPhoto {
        PreparedPhoto(fileURL: URL(filePath: "/tmp/\(name).jpg"), sha256: name, size: 1, width: 1600, height: 1200, mimeType: .jpeg, perceptualHash: 0)
    }

    private func analysis(for photo: PreparedPhoto, room: RoomType) -> AnalysisResult {
        AnalysisResult(photoID: photo.id, qualityScore: 0.9, sharpness: 0.9, exposure: 0.5, noise: 1, warnings: [], room: room,
                       roomConfidence: 0.9, focus: CGRect(x: 0, y: 0, width: 1, height: 1), faces: [])
    }

    private func model(
        renderer: FakeRenderer? = nil, drafts: FakeDrafts = FakeDrafts(), isPro: Bool = false, power: FakePower = FakePower()
    ) -> (VideoEditorModel, FakeRenderer, FakeDrafts) {
        let renderer = renderer ?? FakeRenderer(templates: [classic, social, premium])
        let photos = ["a", "b", "c"].map(photo)
        let analyses = [photos[0].id: analysis(for: photos[0], room: .kitchen)]
        let model = VideoEditorModel(
            photos: photos, analyses: analyses, renderer: renderer, drafts: drafts, power: power,
            isPro: isPro, watermark: !isPro, premiumSlugs: [premium.slug],
            captionForRoom: { $0 == .kitchen ? "Cozinha" : "Outro" }
        )
        return (model, renderer, drafts)
    }

    // MARK: Template

    @Test func premiumTemplateWithoutEntitlementOpensPaywall() {
        let (model, _, _) = model()
        model.selectTemplate(premium.slug)
        #expect(model.paywallRequested)
        #expect(model.templateSlug == classic.slug)
    }

    @Test func proUsersCanPickPremiumTemplatesAndFormatsFollowTheTemplate() {
        let (model, _, _) = model(isPro: true)
        model.toggleFormat(.horizontal)
        #expect(model.formats == [.vertical, .horizontal])

        model.selectTemplate(social.slug)
        #expect(model.formats == [.vertical], "dynamic-social is vertical only")
        model.selectTemplate(premium.slug)
        #expect(!model.paywallRequested)
        #expect(model.formats == [.horizontal])
    }

    // MARK: Script

    @Test func captionsDefaultToRoomNamesAndAreSanitized() {
        let (model, _, _) = model()
        #expect(model.scenes.map(\.caption) == ["Cozinha", "", ""])

        let id = model.scenes[1].id
        model.setCaption(id, "  Sala\ncom vista \u{202E}mar " + String(repeating: "x", count: 100))
        #expect(model.scenes[1].caption.count == VideoEditorModel.captionLimit)
        #expect(!model.scenes[1].caption.contains("\n"))
        #expect(!model.scenes[1].caption.unicodeScalars.contains { $0.value == 0x202E })
        #expect(model.scenes[1].caption.hasPrefix("Salacom vista mar"))
    }

    @Test func reorderingDuplicatingAndRemovingScenes() {
        let (model, _, _) = model()
        let ids = model.scenes.map(\.id)

        model.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(model.scenes.map(\.id) == [ids[2], ids[0], ids[1]])
        model.moveDown(ids[2])
        #expect(model.scenes.map(\.id) == [ids[0], ids[2], ids[1]])
        model.moveUp(ids[0])
        #expect(model.scenes.map(\.id) == [ids[0], ids[2], ids[1]], "first scene can't move up")

        model.duplicate(ids[0])
        #expect(model.scenes.count == 4)
        #expect(model.scenes[1].photo == model.scenes[0].photo)
        #expect(model.scenes[1].id != model.scenes[0].id)

        for id in model.scenes.map(\.id) { model.remove(id) }
        #expect(model.scenes.count == 1, "the last scene can't be removed")
    }

    @Test func durationsAndTextsRespectLimits() {
        let (model, _, _) = model()
        let id = model.scenes[0].id
        model.setDuration(id, milliseconds: 100)
        #expect(model.scenes[0].durationMs == 1_000)
        model.setDuration(id, milliseconds: 60_000)
        #expect(model.scenes[0].durationMs == 8_000)
        #expect(model.totalDurationMs == 8_000 + 3_500 * 2)

        model.setOpeningText(String(repeating: "a", count: 200))
        model.setClosingText("Reserve\tjá")
        #expect(model.openingText.count == VideoEditorModel.textLimit)
        #expect(model.closingText == "Reserveja".replacingOccurrences(of: "ja", with: "já"))
    }

    @Test func lastFormatCannotBeDeselected() {
        let (model, _, _) = model()
        model.toggleFormat(.vertical)
        #expect(model.formats == [.vertical])
    }

    // MARK: Draft

    @Test func changesAreSavedAndDraftRestores() async throws {
        let drafts = FakeDrafts()
        let (model, renderer, _) = model(drafts: drafts)
        model.setOpeningText("Casa de praia")
        model.setCaption(model.scenes[1].id, "Sala")
        try await Task.sleep(for: .milliseconds(800))

        let saved = try #require(await drafts.saved)
        #expect(saved.openingText == "Casa de praia")
        #expect(await drafts.saves == 1, "edits are debounced into one save")

        let restored = VideoEditorModel(draft: saved, renderer: renderer, drafts: drafts, power: FakePower(), isPro: false, watermark: true)
        #expect(restored.scenes.map(\.caption) == ["Cozinha", "Sala", ""])
        #expect(restored.openingText == "Casa de praia")
        #expect(restored.step == .script)
    }

    // MARK: Preview and export

    @Test func previewUsesProxyQualityAndIsInvalidatedByEdits() async {
        let (model, renderer, _) = model()
        model.renderPreview()
        await model.waitForRendering()

        #expect(renderer.requests.last?.quality == .preview)
        #expect(model.previewURL != nil)

        model.setCaption(model.scenes[0].id, "Nova legenda")
        #expect(model.previewURL == nil)
        #expect(renderer.discarded.count == 1)
    }

    @Test func exportRendersEveryFormatAndClearsTheDraft() async {
        let drafts = FakeDrafts()
        let (model, renderer, _) = model(drafts: drafts)
        model.toggleFormat(.horizontal)
        model.setOpeningText("Título")
        model.export()
        await model.waitForRendering()

        guard case .finished(let videos) = model.exportState else {
            Issue.record("expected finished, got \(model.exportState)")
            return
        }
        #expect(videos.map(\.aspect) == [.vertical, .horizontal])
        #expect(renderer.requests.map(\.quality) == [.final, .final])
        #expect(renderer.requests.first?.title == "Título")
        #expect(renderer.requests.first?.watermark == true)
        #expect(renderer.requests.first?.scenes.map(\.caption) == ["Cozinha", nil, nil])
        #expect(await drafts.deletes == 1)
        #expect(!model.isPausedForHeat)
    }

    @Test func exportFailureIsReported() async {
        let (model, _, _) = model(renderer: FakeRenderer(templates: [classic], failWith: .insufficientStorage))
        model.export()
        await model.waitForRendering()
        #expect(model.exportState == .failed(.insufficientStorage))
    }

    @Test func cancellingStopsTheExport() async throws {
        let (model, _, _) = model(renderer: FakeRenderer(templates: [classic], steps: 50))
        model.export()
        try await Task.sleep(for: .milliseconds(60))
        #expect(model.isBusy)
        model.cancelRendering()
        #expect(model.exportState == .idle)
        #expect(!model.isBusy)
    }

    @Test func remainingTimeEstimate() {
        #expect(VideoEditorModel.remaining(elapsed: 10, progress: 0.25) == 30)
        #expect(VideoEditorModel.remaining(elapsed: 0.5, progress: 0.5) == nil)
        #expect(VideoEditorModel.remaining(elapsed: 10, progress: 0.01) == nil)
    }

    @Test func powerWarningComesFromTheProvider() {
        #expect(model(power: FakePower(low: true)).0.shouldWarnAboutPower)
        #expect(!model().0.shouldWarnAboutPower)
    }
}
