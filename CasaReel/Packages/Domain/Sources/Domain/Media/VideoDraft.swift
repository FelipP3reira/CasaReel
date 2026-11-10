import Foundation

/// The editor's work in progress, saved locally so it survives the app being closed.
/// Holds references to the prepared (sanitized) photo files, never the original library assets.
public struct VideoDraft: Codable, Sendable, Equatable {
    public struct Scene: Codable, Sendable, Equatable, Identifiable {
        public let id: UUID
        public var photo: PreparedPhoto
        public var analysis: AnalysisResult?
        public var caption: String
        public var durationMs: Int

        public init(id: UUID = UUID(), photo: PreparedPhoto, analysis: AnalysisResult?, caption: String, durationMs: Int) {
            self.id = id
            self.photo = photo
            self.analysis = analysis
            self.caption = caption
            self.durationMs = durationMs
        }
    }

    public var templateSlug: TemplateSlug
    public var formats: [VideoAspect]
    public var scenes: [Scene]
    public var openingText: String
    public var closingText: String
    public var updatedAt: Date

    public init(
        templateSlug: TemplateSlug, formats: [VideoAspect], scenes: [Scene],
        openingText: String = "", closingText: String = "", updatedAt: Date = Date()
    ) {
        self.templateSlug = templateSlug
        self.formats = formats
        self.scenes = scenes
        self.openingText = openingText
        self.closingText = closingText
        self.updatedAt = updatedAt
    }

    /// Prepared photo files this draft still needs (they must not be purged at launch).
    public var photoFiles: [URL] { scenes.map(\.photo.fileURL) }
}

/// Saves the single current draft (implemented by `Persistence` with SwiftData).
public protocol VideoDraftStoring: Sendable {
    func load() async -> VideoDraft?
    func save(_ draft: VideoDraft) async
    func delete() async
}
