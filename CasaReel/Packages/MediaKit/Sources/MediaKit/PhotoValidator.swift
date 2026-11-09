import Domain
import Foundation
import ImageIO

/// Identifies the real format from the file's first bytes; the extension and the picker's UTI are ignored.
enum ImageFormatSniffer {
    private static let heifBrands: Set<String> = ["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"]

    static func format(ofFileAt url: URL) -> ImageMimeType? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 16) else { return nil }
        return format(of: [UInt8](header))
    }

    static func format(of bytes: [UInt8]) -> ImageMimeType? {
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        // ISO BMFF: [size:4]["ftyp"][major brand:4]
        if bytes.count >= 12, bytes[4..<8].elementsEqual(Array("ftyp".utf8)),
           let brand = String(bytes: bytes[8..<12], encoding: .ascii), heifBrands.contains(brand) {
            return .heic
        }
        return nil
    }
}

/// What the validator learned without decoding pixels.
struct ImageInfo: Equatable {
    let format: ImageMimeType
    let pixelWidth: Int
    let pixelHeight: Int
}

/// Rejects files before any full decode: type by magic bytes, file size, and dimensions read from the header.
struct PhotoValidator: Sendable {
    func validate(fileAt url: URL) throws(PhotoRejection) -> ImageInfo {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0 else { throw .unreadable }
        guard size <= PhotoLimits.maximumFileBytes else { throw .fileTooLarge }
        guard let format = ImageFormatSniffer.format(ofFileAt: url) else { throw .unsupportedType }

        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, options),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { throw .unreadable }

        guard width * height <= PhotoLimits.maximumPixels else { throw .tooManyPixels }
        guard max(width, height) >= PhotoLimits.minimumLongSide else { throw .tooSmall }
        return ImageInfo(format: format, pixelWidth: width, pixelHeight: height)
    }
}
