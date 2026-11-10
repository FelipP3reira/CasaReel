import Domain
import Foundation
import Observation

/// Battery and power status, injectable for tests (`UIDevice` in the app).
public protocol PowerStatusProviding: Sendable {
    /// True when the battery is low and not charging, or Low Power Mode is on.
    @MainActor var shouldWarn: Bool { get }
}

/// The four-step video editor: template → script → customization → preview and export.
@Observable
@MainActor
public final class VideoEditorModel {
    public enum Step: Int, CaseIterable, Sendable {
        case template, script, customize, export
    }

    public struct Scene: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let photo: PreparedPhoto
        public let analysis: AnalysisResult?
        public internal(set) var caption: String
        public internal(set) var durationMs: Int
    }

    public enum ExportState: Equatable, Sendable {
        case idle
        case rendering(progress: Double, format: VideoAspect, secondsRemaining: Int?)
        case finished([RenderedVideo])
        case failed(RenderError)
    }

    public static let captionLimit = 40
    public static let textLimit = 60
    public static let durationRangeMs = 1_000...8_000
    public static let durationStepMs = 500

    // MARK: State

    public var step: Step = .template
    /// `nil` only if the renderer offers no templates at all.
    public private(set) var templateSlug: TemplateSlug?
    public private(set) var formats: Set<VideoAspect>
    public private(set) var scenes: [Scene]
    public private(set) var openingText = ""
    public private(set) var closingText = ""
    /// Set when a premium template is picked without the entitlement; the app shows the paywall.
    public var paywallRequested = false
    public private(set) var previewURL: URL?
    public private(set) var isRenderingPreview = false
    public private(set) var exportState: ExportState = .idle
    public private(set) var isPausedForHeat = false

    public let templates: [VideoTemplateInfo]
    public let premiumSlugs: Set<TemplateSlug>
    public let isPro: Bool
    public let watermark: Bool

    private let renderer: any VideoRenderer
    private let drafts: any VideoDraftStoring
    private let power: any PowerStatusProviding
    private var saveTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var previewVideo: RenderedVideo?

    // MARK: Init

    /// Starts a new project from prepared photos; captions default to the localized room names.
    public init(
        photos: [PreparedPhoto], analyses: [UUID: AnalysisResult], renderer: any VideoRenderer, drafts: any VideoDraftStoring,
        power: any PowerStatusProviding, isPro: Bool, watermark: Bool, premiumSlugs: Set<TemplateSlug> = [],
        captionForRoom: (RoomType) -> String = { _ in "" }
    ) {
        self.renderer = renderer
        self.drafts = drafts
        self.power = power
        self.isPro = isPro
        self.watermark = watermark
        self.premiumSlugs = premiumSlugs
        templates = renderer.templates
        let first = renderer.templates.first { !premiumSlugs.contains($0.slug) } ?? renderer.templates.first
        templateSlug = first?.slug
        formats = Set(first?.aspects.prefix(1) ?? [.vertical])
        scenes = photos.map { photo in
            let analysis = analyses[photo.id]
            return Scene(id: UUID(), photo: photo, analysis: analysis,
                         caption: Self.sanitize(analysis.map { captionForRoom($0.room) } ?? "", limit: Self.captionLimit),
                         durationMs: 3_500)
        }
    }

    /// Restores a saved draft.
    public convenience init(
        draft: VideoDraft, renderer: any VideoRenderer, drafts: any VideoDraftStoring, power: any PowerStatusProviding,
        isPro: Bool, watermark: Bool, premiumSlugs: Set<TemplateSlug> = []
    ) {
        self.init(photos: [], analyses: [:], renderer: renderer, drafts: drafts, power: power,
                  isPro: isPro, watermark: watermark, premiumSlugs: premiumSlugs)
        if templates.contains(where: { $0.slug == draft.templateSlug }) { templateSlug = draft.templateSlug }
        formats = Set(draft.formats).intersection(supportedFormats)
        if formats.isEmpty { formats = [supportedFormats.first ?? .vertical] }
        scenes = draft.scenes.map {
            Scene(id: $0.id, photo: $0.photo, analysis: $0.analysis,
                  caption: Self.sanitize($0.caption, limit: Self.captionLimit), durationMs: Self.clampDuration($0.durationMs))
        }
        openingText = Self.sanitize(draft.openingText, limit: Self.textLimit)
        closingText = Self.sanitize(draft.closingText, limit: Self.textLimit)
        step = .script
    }

    // MARK: Derived

    public var selectedTemplate: VideoTemplateInfo? { templates.first { $0.slug == templateSlug } }
    public var supportedFormats: [VideoAspect] { selectedTemplate?.aspects ?? [.vertical] }
    public var totalDurationMs: Int { scenes.reduce(0) { $0 + $1.durationMs } }
    public var canExport: Bool { templateSlug != nil && !scenes.isEmpty && !formats.isEmpty && !isBusy }
    public var isBusy: Bool {
        if isRenderingPreview { return true }
        if case .rendering = exportState { return true }
        return false
    }
    public var shouldWarnAboutPower: Bool { power.shouldWarn }

    public func isPremium(_ template: VideoTemplateInfo) -> Bool { premiumSlugs.contains(template.slug) }

    // MARK: Step 1: template

    public func selectTemplate(_ slug: TemplateSlug) {
        guard let template = templates.first(where: { $0.slug == slug }) else { return }
        if isPremium(template), !isPro {
            paywallRequested = true
            return
        }
        templateSlug = slug
        formats = formats.intersection(template.aspects)
        if formats.isEmpty, let first = template.aspects.first { formats = [first] }
        invalidatePreview()
        scheduleSave()
    }

    // MARK: Step 2: script

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        scenes.move(fromOffsets: source, toOffset: destination)
        changed()
    }

    /// VoiceOver custom actions.
    public func moveUp(_ id: UUID) {
        guard let index = scenes.firstIndex(where: { $0.id == id }), index > 0 else { return }
        scenes.swapAt(index, index - 1)
        changed()
    }

    public func moveDown(_ id: UUID) {
        guard let index = scenes.firstIndex(where: { $0.id == id }), index < scenes.count - 1 else { return }
        scenes.swapAt(index, index + 1)
        changed()
    }

    public func remove(_ id: UUID) {
        guard scenes.count > 1 else { return }
        scenes.removeAll { $0.id == id }
        changed()
    }

    public func duplicate(_ id: UUID) {
        guard let index = scenes.firstIndex(where: { $0.id == id }), scenes.count < PhotoLimits.maximumCount else { return }
        var copy = scenes[index]
        copy = Scene(id: UUID(), photo: copy.photo, analysis: copy.analysis, caption: copy.caption, durationMs: copy.durationMs)
        scenes.insert(copy, at: index + 1)
        changed()
    }

    public func setDuration(_ id: UUID, milliseconds: Int) {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        scenes[index].durationMs = Self.clampDuration(milliseconds)
        changed()
    }

    public func setCaption(_ id: UUID, _ text: String) {
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        scenes[index].caption = Self.sanitize(text, limit: Self.captionLimit)
        changed()
    }

    // MARK: Step 3: customization

    public func setOpeningText(_ text: String) {
        openingText = Self.sanitize(text, limit: Self.textLimit)
        changed()
    }

    public func setClosingText(_ text: String) {
        closingText = Self.sanitize(text, limit: Self.textLimit)
        changed()
    }

    public func toggleFormat(_ format: VideoAspect) {
        guard supportedFormats.contains(format) else { return }
        if formats.contains(format) {
            guard formats.count > 1 else { return }
            formats.remove(format)
        } else {
            formats.insert(format)
        }
        changed()
    }

    // MARK: Step 4: preview and export

    public func renderPreview() {
        guard !isBusy, let format = orderedFormats.first, let request = request(for: format, quality: .preview) else { return }
        isRenderingPreview = true
        renderTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isRenderingPreview = false }
            do {
                for try await event in renderer.render(request) {
                    if case .finished(let video) = event {
                        if let old = previewVideo { renderer.discard(old) }
                        previewVideo = video
                        previewURL = video.fileURL
                    }
                }
            } catch {
                exportState = .failed((error as? RenderError) ?? .writerFailed)
            }
        }
    }

    public func export() {
        guard canExport else { return }
        let formatsToRender = orderedFormats
        exportState = .rendering(progress: 0, format: formatsToRender[0], secondsRemaining: nil)
        renderTask = Task { [weak self] in
            guard let self else { return }
            var results: [RenderedVideo] = []
            let started = Date()
            do {
                for (index, format) in formatsToRender.enumerated() {
                    guard let request = request(for: format, quality: .final) else { throw RenderError.unknownTemplate }
                    for try await event in renderer.render(request) {
                        switch event {
                        case .progress(let value):
                            isPausedForHeat = false
                            let overall = (Double(index) + value) / Double(formatsToRender.count)
                            exportState = .rendering(progress: overall, format: format,
                                                     secondsRemaining: Self.remaining(elapsed: Date().timeIntervalSince(started), progress: overall))
                        case .pausedForHeat:
                            isPausedForHeat = true
                        case .finished(let video):
                            results.append(video)
                        }
                    }
                }
                try Task.checkCancellation()
                exportState = .finished(results)
                await drafts.delete()
            } catch {
                results.forEach(renderer.discard)
                exportState = Task.isCancelled ? .idle : .failed((error as? RenderError) ?? .writerFailed)
            }
            isPausedForHeat = false
        }
    }

    public func cancelRendering() {
        renderTask?.cancel()
        renderTask = nil
        isRenderingPreview = false
        exportState = .idle
        isPausedForHeat = false
    }

    /// Waits for the current preview or export (tests).
    public func waitForRendering() async {
        await renderTask?.value
    }

    /// Saves now (e.g. when the app goes to background).
    public func saveDraft() async {
        saveTask?.cancel()
        if let draft { await drafts.save(draft) }
    }

    public var draft: VideoDraft? {
        guard let templateSlug else { return nil }
        return VideoDraft(
            templateSlug: templateSlug, formats: orderedFormats,
            scenes: scenes.map { .init(id: $0.id, photo: $0.photo, analysis: $0.analysis, caption: $0.caption, durationMs: $0.durationMs) },
            openingText: openingText, closingText: closingText
        )
    }

    // MARK: Helpers

    var orderedFormats: [VideoAspect] {
        VideoAspect.allCases.filter(formats.contains)
    }

    func request(for format: VideoAspect, quality: RenderQuality) -> VideoRenderRequest? {
        guard let templateSlug else { return nil }
        return VideoRenderRequest(
            scenes: scenes.map { VideoScene(photo: $0.photo, caption: $0.caption.isEmpty ? nil : $0.caption, durationMs: $0.durationMs) },
            analyses: Dictionary(scenes.compactMap { scene in scene.analysis.map { (scene.photo.id, $0) } }, uniquingKeysWith: { first, _ in first }),
            templateSlug: templateSlug, aspect: format,
            title: openingText.isEmpty ? nil : openingText,
            closingText: closingText.isEmpty ? nil : closingText,
            watermark: watermark, quality: quality
        )
    }

    private func changed() {
        invalidatePreview()
        scheduleSave()
    }

    private func invalidatePreview() {
        if let old = previewVideo { renderer.discard(old) }
        previewVideo = nil
        previewURL = nil
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, let draft = self.draft else { return }
            await self.drafts.save(draft)
        }
    }

    /// Plain text only: no newlines or control/bidi characters, trimmed and limited.
    static func sanitize(_ text: String, limit: Int) -> String {
        let cleaned = text.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && !(0x202A...0x202E).contains(scalar.value) && !(0x2066...0x2069).contains(scalar.value)
        }
        return String(String(String.UnicodeScalarView(cleaned)).trimmingCharacters(in: .whitespaces).prefix(limit))
    }

    static func clampDuration(_ milliseconds: Int) -> Int {
        min(max(milliseconds, durationRangeMs.lowerBound), durationRangeMs.upperBound)
    }

    static func remaining(elapsed: TimeInterval, progress: Double) -> Int? {
        guard progress > 0.03, elapsed > 1 else { return nil }
        return Int((elapsed / progress - elapsed).rounded())
    }
}
