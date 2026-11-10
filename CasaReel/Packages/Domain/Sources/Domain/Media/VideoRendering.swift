import Foundation

/// Output format of a rendered video.
public enum VideoAspect: String, Codable, Sendable, CaseIterable {
    case vertical = "9:16"
    case horizontal = "16:9"

    /// Pixel size of the export (1080p).
    public var renderSize: (width: Int, height: Int) {
        switch self {
        case .vertical: (1080, 1920)
        case .horizontal: (1920, 1080)
        }
    }

    public func renderSize(for quality: RenderQuality) -> (width: Int, height: Int) {
        let size = renderSize
        return quality == .final ? size : (size.width / 2, size.height / 2)
    }
}

/// What the editor shows for each available template.
public struct VideoTemplateInfo: Sendable, Equatable, Identifiable {
    public let slug: TemplateSlug
    public let version: Int
    public let aspects: [VideoAspect]
    /// Duration of the template's scene pattern, for display only.
    public let sceneCount: Int

    public var id: String { slug.rawValue }

    public init(slug: TemplateSlug, version: Int, aspects: [VideoAspect], sceneCount: Int) {
        self.slug = slug
        self.version = version
        self.aspects = aspects
        self.sceneCount = sceneCount
    }
}

/// One shot of the video. The same photo may appear in several scenes (duplicated in the editor).
public struct VideoScene: Sendable, Equatable {
    public let photo: PreparedPhoto
    /// Plain text shown on the scene (e.g. the room name); never interpreted.
    public let caption: String?
    /// Overrides the template's duration for this scene (clamped to 1–8 s).
    public let durationMs: Int?

    public init(photo: PreparedPhoto, caption: String? = nil, durationMs: Int? = nil) {
        self.photo = photo
        self.caption = caption
        self.durationMs = durationMs
    }
}

public enum RenderQuality: Sendable, Equatable {
    /// Full 1080p export.
    case final
    /// Half-size (540p) proxy for the in-app preview: 4× fewer pixels, much faster.
    case preview
}

/// Everything needed to render one video. Texts are shown as plain text, never interpreted.
public struct VideoRenderRequest: Sendable {
    public let scenes: [VideoScene]
    public let analyses: [UUID: AnalysisResult]
    public let templateSlug: TemplateSlug
    public let aspect: VideoAspect
    /// Optional opening title (e.g. the property name).
    public let title: String?
    /// Optional closing text shown over the last seconds (e.g. "Reserve pelo link na bio").
    public let closingText: String?
    /// Required by the plan (`Entitlements.limits.watermark`); the server verifies it again on registration.
    public let watermark: Bool
    /// Desired total duration; the template's scene durations are scaled to approach it (1–8 s per scene).
    public let targetDurationMs: Int?
    /// Local audio file from the signed music library, or `nil` for a silent video.
    public let audioTrackURL: URL?
    public let quality: RenderQuality

    public init(
        scenes: [VideoScene], analyses: [UUID: AnalysisResult] = [:], templateSlug: TemplateSlug, aspect: VideoAspect,
        title: String? = nil, closingText: String? = nil, watermark: Bool, targetDurationMs: Int? = nil,
        audioTrackURL: URL? = nil, quality: RenderQuality = .final
    ) {
        self.scenes = scenes
        self.analyses = analyses
        self.templateSlug = templateSlug
        self.aspect = aspect
        self.title = title
        self.closingText = closingText
        self.watermark = watermark
        self.targetDurationMs = targetDurationMs
        self.audioTrackURL = audioTrackURL
        self.quality = quality
    }

    /// One scene per photo, with an optional caption per photo id.
    public init(
        photos: [PreparedPhoto], analyses: [UUID: AnalysisResult] = [:], templateSlug: TemplateSlug, aspect: VideoAspect,
        captions: [UUID: String] = [:], title: String? = nil, watermark: Bool, targetDurationMs: Int? = nil, audioTrackURL: URL? = nil
    ) {
        self.init(
            scenes: photos.map { VideoScene(photo: $0, caption: captions[$0.id]) }, analyses: analyses,
            templateSlug: templateSlug, aspect: aspect, title: title, watermark: watermark,
            targetDurationMs: targetDurationMs, audioTrackURL: audioTrackURL
        )
    }

    public var photos: [PreparedPhoto] { scenes.map(\.photo) }
}

public struct RenderedVideo: Sendable, Equatable {
    public let fileURL: URL
    public let thumbnailURL: URL
    public let templateSlug: TemplateSlug
    public let templateVersion: Int
    public let aspect: VideoAspect
    public let durationMs: Int
    public let sizeBytes: Int
    /// Lowercase hex SHA-256 of the video file (sent when registering it).
    public let sha256: String
    public let watermark: Bool

    public init(
        fileURL: URL, thumbnailURL: URL, templateSlug: TemplateSlug, templateVersion: Int, aspect: VideoAspect,
        durationMs: Int, sizeBytes: Int, sha256: String, watermark: Bool
    ) {
        self.fileURL = fileURL
        self.thumbnailURL = thumbnailURL
        self.templateSlug = templateSlug
        self.templateVersion = templateVersion
        self.aspect = aspect
        self.durationMs = durationMs
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.watermark = watermark
    }
}

public enum RenderEvent: Sendable, Equatable {
    /// 0–1.
    case progress(Double)
    /// The device is hot; rendering waits until it cools down.
    case pausedForHeat
    case finished(RenderedVideo)
}

public enum RenderError: Error, Sendable, Equatable {
    case unknownTemplate
    case unsupportedAspect
    case invalidTemplate(String)
    case notEnoughPhotos
    case unreadablePhoto
    /// The device stayed critically hot; the partial file was removed.
    case overheated
    case cancelled
    case writerFailed
    /// Not enough free space for the export.
    case insufficientStorage
}

/// On-device video composition and export (implemented by `VideoEngine`).
public protocol VideoRenderer: Sendable {
    var templates: [VideoTemplateInfo] { get }
    /// One render at a time; a new call waits for the previous one. Cancelling the consuming task cancels the render.
    func render(_ request: VideoRenderRequest) -> AsyncThrowingStream<RenderEvent, any Error>
    func discard(_ video: RenderedVideo)
}
