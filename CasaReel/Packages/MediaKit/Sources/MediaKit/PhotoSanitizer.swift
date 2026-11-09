import CoreGraphics
import CryptoKit
import Domain
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Re-encodes a validated photo into a fresh JPEG that carries pixels and color profile only.
///
/// Decoding goes through `CGImageSourceCreateThumbnailAtIndex`, which downsamples while decoding
/// (memory stays proportional to the output, not the original) and bakes the EXIF orientation into
/// the pixels. The new image is written with no source properties, so EXIF, GPS, TIFF, IPTC and
/// MakerApple dictionaries never reach the output.
struct PhotoSanitizer: Sendable {
    static let jpegQuality = 0.9

    struct Output {
        let width: Int
        let height: Int
    }

    func sanitize(_ input: URL, info: ImageInfo, to output: URL) throws(PhotoRejection) -> Output {
        let longSide = min(max(info.pixelWidth, info.pixelHeight), PhotoLimits.outputLongSide)
        guard let image = Self.decode(input, maxPixelSize: longSide) else { throw .unreadable }

        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw .unreadable
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: Self.jpegQuality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw .unreadable
        }
        return Output(width: image.width, height: image.height)
    }

    static func decode(_ url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

enum FileHasher {
    /// SHA-256 streamed in 1 MB chunks, so large files never sit in memory.
    static func sha256(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Difference hash: compare adjacent pixels of a 9×8 grayscale thumbnail. Robust to resizing and re-compression.
enum PerceptualHash {
    static func dHash(ofFileAt url: URL) -> UInt64? {
        guard let thumbnail = PhotoSanitizer.decode(url, maxPixelSize: 64) else { return nil }
        let width = 9, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var hash: UInt64 = 0
        for row in 0..<height {
            for column in 0..<(width - 1) {
                hash <<= 1
                if pixels[row * width + column] > pixels[row * width + column + 1] { hash |= 1 }
            }
        }
        return hash
    }
}
