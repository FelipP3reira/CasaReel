import Domain
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MediaKit

final class PhotoPreparationTests {
    private let base: URL
    private let service: PhotoPreparationService

    init() throws {
        base = try Fixtures.directory()
        service = PhotoPreparationService(baseDirectory: base)
        try FileManager.default.createDirectory(at: service.stagingDirectory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: base)
    }

    private func staged(_ name: String) -> URL {
        service.stagingDirectory.appending(path: name)
    }

    // MARK: Sanitization

    @Test func removesGPSAndAllMetadata() async throws {
        let input = staged("gps.jpg")
        try Fixtures.jpegWithMetadata(at: input)
        #expect(Fixtures.properties(of: input)[kCGImagePropertyGPSDictionary] != nil)

        let photo = try await service.prepare(fileAt: input)
        let output = Fixtures.properties(of: photo.fileURL)

        #expect(output[kCGImagePropertyGPSDictionary] == nil)
        #expect(output[kCGImagePropertyIPTCDictionary] == nil)
        #expect(output[kCGImagePropertyMakerAppleDictionary] == nil)
        let tiff = output[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        #expect(tiff[kCGImagePropertyTIFFMake] == nil)
        #expect(tiff[kCGImagePropertyTIFFModel] == nil)
        let exif = output[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifUserComment] == nil)
        // The address in the EXIF comment must not survive anywhere in the file.
        let bytes = try Data(contentsOf: photo.fileURL)
        #expect(bytes.range(of: Data("Rua X".utf8)) == nil)
    }

    @Test func returnsHashSizeAndDimensions() async throws {
        let input = staged("photo.jpg")
        try Fixtures.jpegWithMetadata(at: input)

        let photo = try await service.prepare(fileAt: input)

        #expect(photo.mimeType == .jpeg)
        #expect((photo.width, photo.height) == (1600, 1200))
        #expect(photo.size == (try Data(contentsOf: photo.fileURL)).count)
        #expect(photo.sha256 == (try FileHasher.sha256(ofFileAt: photo.fileURL)))
        #expect(photo.sha256.wholeMatch(of: /[0-9a-f]{64}/) != nil)
        #expect(!FileManager.default.fileExists(atPath: input.path), "staged original must be deleted")
    }

    @Test func appliesOrientationToPixels() async throws {
        let input = staged("rotated.jpg")
        try Fixtures.jpegWithMetadata(at: input, width: 1600, height: 1200, orientation: 6)

        let photo = try await service.prepare(fileAt: input)

        #expect((photo.width, photo.height) == (1200, 1600))
        let orientation = Fixtures.properties(of: photo.fileURL)[kCGImagePropertyOrientation] as? Int
        #expect(orientation == nil || orientation == 1)
    }

    @Test func downscalesToMaximumLongSide() async throws {
        let input = staged("big.jpg")
        let image = try #require(Fixtures.image(width: 6000, height: 4000))
        #expect(Fixtures.write(image, to: input, type: .jpeg))

        let photo = try await service.prepare(fileAt: input)
        #expect(max(photo.width, photo.height) == PhotoLimits.outputLongSide)
    }

    @Test func acceptsPNGEvenWithJPGExtension() async throws {
        let input = staged("really-a-png.jpg")
        let image = try #require(Fixtures.image(width: 1400, height: 1000))
        #expect(Fixtures.write(image, to: input, type: .png))
        #expect(ImageFormatSniffer.format(ofFileAt: input) == .png)

        let photo = try await service.prepare(fileAt: input)
        #expect(photo.mimeType == .jpeg)
    }

    @Test func acceptsHEICWhenTheEncoderIsAvailable() async throws {
        let input = staged("photo.heic")
        let image = try #require(Fixtures.image(width: 1600, height: 1200))
        guard Fixtures.write(image, to: input, type: .heic) else { return }  // no HEIC encoder on this host
        #expect(ImageFormatSniffer.format(ofFileAt: input) == .heic)
        #expect(try await service.prepare(fileAt: input).mimeType == .jpeg)
    }

    // MARK: Rejections

    @Test func rejectsCorruptedFile() async throws {
        let input = staged("broken.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0x42, count: 512)).write(to: input)
        await #expect(throws: PhotoRejection.unreadable) { try await self.service.prepare(fileAt: input) }
        #expect(!FileManager.default.fileExists(atPath: input.path))
    }

    @Test func rejectsUnknownFormat() async throws {
        let input = staged("notes.jpg")
        try Data("not an image at all".utf8).write(to: input)
        await #expect(throws: PhotoRejection.unsupportedType) { try await self.service.prepare(fileAt: input) }
    }

    @Test func rejectsDecompressionBomb() async throws {
        let input = staged("bomb.jpg")
        #expect(Fixtures.oversizedGrayJPEG(at: input))
        await #expect(throws: PhotoRejection.tooManyPixels) { try await self.service.prepare(fileAt: input) }
    }

    @Test func rejectsSmallImages() async throws {
        let input = staged("small.jpg")
        let image = try #require(Fixtures.image(width: 800, height: 600))
        #expect(Fixtures.write(image, to: input, type: .jpeg))
        await #expect(throws: PhotoRejection.tooSmall) { try await self.service.prepare(fileAt: input) }
    }

    @Test func rejectsOversizedFiles() async throws {
        let input = staged("huge.jpg")
        var data = Data([0xFF, 0xD8, 0xFF])
        data.append(Data(count: PhotoLimits.maximumFileBytes))
        try data.write(to: input)
        await #expect(throws: PhotoRejection.fileTooLarge) { try await self.service.prepare(fileAt: input) }
    }

    @Test func rejectsEmptyOrMissingFiles() async throws {
        await #expect(throws: PhotoRejection.unreadable) { try await self.service.prepare(fileAt: self.staged("missing.jpg")) }
    }

    // MARK: Duplicates and cleanup

    @Test func detectsExactAndSimilarDuplicates() async throws {
        let original = staged("a.jpg"), copy = staged("b.jpg"), shifted = staged("c.jpg"), different = staged("d.png")
        try Fixtures.jpegWithMetadata(at: original)
        try FileManager.default.copyItem(at: original, to: copy)
        let nudged = try #require(Fixtures.image(width: 1600, height: 1200, shift: 4))
        #expect(Fixtures.write(nudged, to: shifted, type: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: 0.5]))
        let other = try #require(Fixtures.image(width: 1200, height: 1600, checkerboard: true))
        #expect(Fixtures.write(other, to: different, type: .png))

        let first = try await service.prepare(fileAt: original)
        let second = try await service.prepare(fileAt: copy)
        let third = try await service.prepare(fileAt: shifted)
        let fourth = try await service.prepare(fileAt: different)

        #expect(DuplicateDetector.match(for: second, in: [first]) == .exact)
        #expect(DuplicateDetector.match(for: third, in: [first]) == .similar)
        #expect(DuplicateDetector.match(for: fourth, in: [first]) == nil)
        #expect(DuplicateDetector.match(for: first, in: [first]) == nil, "a photo is not a duplicate of itself")
    }

    @Test func discardRemovesOnlyOwnedFiles() async throws {
        let input = staged("x.jpg")
        try Fixtures.jpegWithMetadata(at: input)
        let photo = try await service.prepare(fileAt: input)

        let outsider = base.appending(path: "outside.txt")
        try Data("keep".utf8).write(to: outsider)
        let forged = PreparedPhoto(fileURL: outsider, sha256: "", size: 0, width: 0, height: 0, mimeType: .jpeg, perceptualHash: 0)

        service.discard(forged)
        service.discard(photo)

        #expect(FileManager.default.fileExists(atPath: outsider.path))
        #expect(!FileManager.default.fileExists(atPath: photo.fileURL.path))
    }

    @Test func discardAllLeavesNoTemporaryFiles() async throws {
        let input = staged("x.jpg")
        try Fixtures.jpegWithMetadata(at: input)
        _ = try await service.prepare(fileAt: input)
        try Data("pending".utf8).write(to: staged("pending.jpg"))

        service.discardAll()

        #expect(!FileManager.default.fileExists(atPath: service.stagingDirectory.deletingLastPathComponent().path))
    }

    @Test func doesNotDeleteFilesOutsideStaging() async throws {
        let outside = base.appending(path: "user.jpg")
        try Fixtures.jpegWithMetadata(at: outside)
        _ = try await service.prepare(fileAt: outside)
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }
}

struct ImageFormatSnifferTests {
    @Test(arguments: [
        ([0xFF, 0xD8, 0xFF, 0xE1], ImageMimeType?.some(.jpeg)),
        ([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], .png),
        ([0, 0, 0, 0x18] + Array("ftypheic".utf8), .heic),
        ([0, 0, 0, 0x18] + Array("ftypmif1".utf8), .heic),
        ([0, 0, 0, 0x18] + Array("ftypmp42".utf8), nil),
        (Array("GIF89a".utf8), nil),
        ([], nil),
    ] as [([UInt8], ImageMimeType?)])
    func sniffsFormat(bytes: [UInt8], expected: ImageMimeType?) {
        #expect(ImageFormatSniffer.format(of: bytes) == expected)
    }
}

struct PhotoBatchPurgeTests {
    @Test func purgeKeepsOnlyBatchesReferencedByTheDraft() throws {
        let base = try Fixtures.directory()
        defer { try? FileManager.default.removeItem(at: base) }
        let kept = base.appending(path: "batch-a/prepared", directoryHint: .isDirectory)
        let dropped = base.appending(path: "batch-b/prepared", directoryHint: .isDirectory)
        for directory in [kept, dropped] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let file = kept.appending(path: "photo.jpg")
        try Data("x".utf8).write(to: file)

        PhotoPreparationService.purgeBatches(in: base, keeping: [file])

        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: base.appending(path: "batch-b").path))
    }
}
