import Foundation
import Observation
import Walk3DKit

/// The Walk 3D flow: gallery photos + videos → package for the Mac → 3D back from the Mac → walk video.
@Observable
@MainActor
public final class Walk3DModel {
    public typealias Export = @Sendable (_ photos: [URL], _ videos: [URL]) -> AsyncThrowingStream<SceneExportEvent, any Error>
    public typealias Render = @Sendable (_ package: URL, _ watermark: Bool) -> AsyncThrowingStream<Walk3DRenderEvent, any Error>

    public enum MediaState: Equatable {
        case empty
        case loading
        case ready(photos: Int, videos: Int)
        case failed
    }

    public enum ExportState: Equatable {
        case idle
        case exporting(progress: Double)
        case exported(SceneExportResult)
        case failed(SceneExportError)
    }

    public enum RenderState: Equatable {
        case idle
        case rendering(progress: Double, pausedForHeat: Bool)
        case finished(Walk3DVideo)
        case failed(Walk3DRenderError)
    }

    public private(set) var media: MediaState = .empty
    public private(set) var exportState: ExportState = .idle
    public private(set) var renderState: RenderState = .idle
    /// The free plan always carries the watermark; the server decides the plan.
    public let watermark: Bool

    private var photos: [URL] = []
    private var videos: [URL] = []
    private let export: Export
    private let render: Render
    private var exportTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?

    public init(watermark: Bool, export: @escaping Export, render: @escaping Render) {
        self.watermark = watermark
        self.export = export
        self.render = render
    }

    public var canExport: Bool {
        guard case .ready(let photos, let videos) = media else { return false }
        return photos + videos > 0 && !isExporting
    }

    public var isExporting: Bool {
        if case .exporting = exportState { return true }
        return false
    }

    public var isRendering: Bool {
        if case .rendering = renderState { return true }
        return false
    }

    // MARK: - Media

    /// Starts loading picked items; `load` returns staged files (or `nil` for an item that failed).
    func loadMedia(count: Int, load: @escaping @Sendable (Int) async -> PickedMedia?) {
        exportTask?.cancel()
        exportState = .idle
        guard count > 0 else {
            setMedia(photos: [], videos: [])
            return
        }
        media = .loading
        Task {
            var photos: [URL] = [], videos: [URL] = []
            for index in 0..<count {
                switch await load(index) {
                case .photo(let url): photos.append(url)
                case .video(let url): videos.append(url)
                case nil: break
                }
            }
            setMedia(photos: photos, videos: videos)
            if photos.isEmpty, videos.isEmpty { media = .failed }
        }
    }

    func setMedia(photos: [URL], videos: [URL]) {
        removeStaged()
        self.photos = photos
        self.videos = videos
        media = photos.isEmpty && videos.isEmpty ? .empty : .ready(photos: photos.count, videos: videos.count)
    }

    // MARK: - Export

    public func exportScene() {
        guard canExport else { return }
        exportState = .exporting(progress: 0)
        let stream = export(photos, videos)
        exportTask = Task {
            do {
                for try await event in stream {
                    switch event {
                    case .progress(let value): exportState = .exporting(progress: value)
                    case .finished(let result): exportState = .exported(result)
                    }
                }
            } catch {
                exportState = .failed(error as? SceneExportError ?? .writeFailed)
            }
        }
    }

    public func cancelExport() {
        exportTask?.cancel()
        exportState = .idle
    }

    // MARK: - Render

    /// Renders the 3D package chosen in the Files picker. The file is copied first: the picker's URL
    /// is only readable while its security scope is open.
    public func renderPackage(at url: URL) {
        renderTask?.cancel()
        let inbox = FileManager.default.temporaryDirectory.appending(path: "CasaReelWalk3DInbox", directoryHint: .isDirectory)
        let copy = inbox.appending(path: "\(UUID().uuidString).aar")
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: copy)
        } catch {
            renderState = .failed(.invalidPackage(.invalidPackage))
            return
        }
        renderState = .rendering(progress: 0, pausedForHeat: false)
        let stream = render(copy, watermark)
        renderTask = Task {
            defer { try? FileManager.default.removeItem(at: copy) }
            do {
                for try await event in stream {
                    switch event {
                    case .progress(let value): renderState = .rendering(progress: value, pausedForHeat: false)
                    case .pausedForHeat:
                        if case .rendering(let progress, _) = renderState { renderState = .rendering(progress: progress, pausedForHeat: true) }
                    case .finished(let video): renderState = .finished(video)
                    }
                }
            } catch {
                renderState = .failed(error as? Walk3DRenderError ?? .writerFailed)
            }
        }
    }

    public func cancelRender() {
        renderTask?.cancel()
        renderState = .idle
    }

    private func removeStaged() {
        for url in photos + videos { try? FileManager.default.removeItem(at: url) }
    }
}

/// A picked gallery item, already copied to a file the app owns.
enum PickedMedia: Sendable {
    case photo(URL)
    case video(URL)
}
