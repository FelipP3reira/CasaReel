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

/// Everything needed to render one video. Captions and title are shown as plain text, never interpreted.
public struct VideoRenderRequest: Sendable {
    public let photos: [PreparedPhoto]
    public let analyses: [UUID: AnalysisResult]
    public let templateSlug: TemplateSlug
    public let aspect: VideoAspect
    /// Caption per photo id (e.g. the localized room name); photos without one show none.
    public let captions: [UUID: String]
    /// Optional opening title (e.g. the property name).
    public let title: String?
    /// Required by the plan (`Entitlements.limits.watermark`); the server verifies it again on registration.
    public let watermark: Bool
    /// Desired total duration; the template's scene durations are scaled to approach it (1–8 s per scene).
    public let targetDurationMs: Int?
    /// Local audio file from the signed music library, or `nil` for a silent video.
    public let audioTrackURL: URL?

    public init(
        photos: [PreparedPhoto], analyses: [UUID: AnalysisResult] = [:], templateSlug: TemplateSlug, aspect: VideoAspect,
        captions: [UUID: String] = [:], title: String? = nil, watermark: Bool, targetDurationMs: Int? = nil, audioTrackURL: URL? = nil
    ) {
        self.photos = photos
        self.analyses = analyses
        self.templateSlug = templateSlug
        self.aspect = aspect
        self.captions = captions
        self.title = title
        self.watermark = watermark
        self.targetDurationMs = targetDurationMs
        self.audioTrackURL = audioTrackURL
    }
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
}

/// On-device video composition and export (implemented by `VideoEngine`).
public protocol VideoRenderer: Sendable {
    var templates: [VideoTemplateInfo] { get }
    /// One render at a time; a new call waits for the previous one. Cancelling the consuming task cancels the render.
    func render(_ request: VideoRenderRequest) -> AsyncThrowingStream<RenderEvent, any Error>
    func discard(_ video: RenderedVideo)
}
