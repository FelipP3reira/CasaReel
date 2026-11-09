import Domain
import Foundation

/// Validates and sanitizes picked photos into a private working directory.
///
/// Files live under `tmp/CasaReelPhotos/<batch>` (never backed up) with `completeUnlessOpen` data protection,
/// and are removed on `discard`, `discardAll` or when the original staged copy has been processed.
public final class PhotoPreparationService: PhotoPreparing {
    public let stagingDirectory: URL
    private let preparedDirectory: URL
    private let root: URL
    private let validator = PhotoValidator()
    private let sanitizer = PhotoSanitizer()

    public init(baseDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "CasaReelPhotos", directoryHint: .isDirectory)) {
        root = baseDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        stagingDirectory = root.appending(path: "staging", directoryHint: .isDirectory)
        preparedDirectory = root.appending(path: "prepared", directoryHint: .isDirectory)
    }

    public func prepare(fileAt url: URL) async throws(PhotoRejection) -> PreparedPhoto {
        // A staged copy is always deleted: accepted photos continue as the sanitized file only.
        defer { if Self.isInside(url, stagingDirectory) { try? FileManager.default.removeItem(at: url) } }
        try ensureDirectories()

        let info = try validator.validate(fileAt: url)
        let id = UUID()
        let output = preparedDirectory.appending(path: "\(id.uuidString).jpg")
        let result = try sanitizer.sanitize(url, info: info, to: output)
        do {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: output.path)
            let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let sha256 = try FileHasher.sha256(ofFileAt: output)
            guard let hash = PerceptualHash.dHash(ofFileAt: output) else { throw PhotoRejection.unreadable }
            return PreparedPhoto(
                id: id, fileURL: output, sha256: sha256, size: size,
                width: result.width, height: result.height, mimeType: .jpeg, perceptualHash: hash
            )
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw .unreadable
        }
    }

    public func discard(_ photo: PreparedPhoto) {
        // Only files inside our own directory may be deleted.
        guard Self.isInside(photo.fileURL, preparedDirectory) else { return }
        try? FileManager.default.removeItem(at: photo.fileURL)
    }

    static func isInside(_ url: URL, _ directory: URL) -> Bool {
        let directoryPath = directory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        return url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(directoryPath)
    }

    public func discardAll() {
        try? FileManager.default.removeItem(at: root)
    }

    private func ensureDirectories() throws(PhotoRejection) {
        do {
            for directory in [stagingDirectory, preparedDirectory] {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
                )
            }
        } catch {
            throw .unreadable
        }
    }
}
