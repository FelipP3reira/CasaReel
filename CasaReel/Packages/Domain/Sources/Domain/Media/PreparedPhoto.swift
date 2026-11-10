import Foundation

/// A photo that passed validation and sanitization: re-encoded, metadata-free and ready to use or upload.
/// Nothing reaches the video engine or the server without going through `PhotoPreparing`.
public struct PreparedPhoto: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let fileURL: URL
    /// Lowercase hex SHA-256 of the sanitized file.
    public let sha256: String
    public let size: Int
    public let width: Int
    public let height: Int
    public let mimeType: ImageMimeType
    /// 64-bit difference hash (dHash) used to spot near-duplicates.
    public let perceptualHash: UInt64

    public init(
        id: UUID = UUID(), fileURL: URL, sha256: String, size: Int,
        width: Int, height: Int, mimeType: ImageMimeType, perceptualHash: UInt64
    ) {
        self.id = id
        self.fileURL = fileURL
        self.sha256 = sha256
        self.size = size
        self.width = width
        self.height = height
        self.mimeType = mimeType
        self.perceptualHash = perceptualHash
    }
}

/// Why a picked file was refused. Carries no file content or path.
public enum PhotoRejection: Error, Sendable, Equatable {
    case unsupportedType
    case fileTooLarge
    case tooSmall
    /// Above the pixel budget; protects against decompression bombs.
    case tooManyPixels
    case unreadable
}

public enum PhotoLimits {
    public static let minimumCount = 5
    public static let maximumCount = 40
    public static let maximumFileBytes = 25 * 1024 * 1024
    /// Required size of the longer side.
    public static let minimumLongSide = 1280
    public static let maximumPixels = 50_000_000
    /// Sanitized photos are downscaled to this longer side.
    public static let outputLongSide = 4096
}

/// Validates and sanitizes picked photos (implemented by `MediaKit`).
public protocol PhotoPreparing: Sendable {
    /// Directory where picked files are copied before preparation; owned and cleaned by the preparer.
    var stagingDirectory: URL { get }
    /// Validates the file, writes a sanitized copy and deletes the original staged file.
    func prepare(fileAt url: URL) async throws(PhotoRejection) -> PreparedPhoto
    func discard(_ photo: PreparedPhoto)
    /// Deletes every staged and prepared file (cancel, sign-out).
    func discardAll()
}

public enum DuplicateMatch: Sendable, Equatable {
    /// Byte-identical after sanitization.
    case exact
    /// Visually the same photo (resized, re-compressed, slightly edited).
    case similar
}

public enum DuplicateDetector {
    /// Hamming distance between dHashes at or below which two photos are treated as the same.
    public static let similarityThreshold = 5

    public static func match(for photo: PreparedPhoto, in others: [PreparedPhoto]) -> DuplicateMatch? {
        let candidates = others.filter { $0.id != photo.id }
        if candidates.contains(where: { $0.sha256 == photo.sha256 }) { return .exact }
        if candidates.contains(where: { distance($0.perceptualHash, photo.perceptualHash) <= similarityThreshold }) {
            return .similar
        }
        return nil
    }

    static func distance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }
}
