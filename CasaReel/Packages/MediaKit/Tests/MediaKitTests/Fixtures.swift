import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Builds test images on the fly so no binary fixtures live in the repo.
enum Fixtures {
    static var gps: [CFString: Any] { [
        kCGImagePropertyGPSLatitude: -23.4339, kCGImagePropertyGPSLatitudeRef: "S",
        kCGImagePropertyGPSLongitude: 45.0711, kCGImagePropertyGPSLongitudeRef: "W",
    ] }

    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "MediaKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A gradient with a bright square, so the dHash has structure. `shift` moves the square slightly.
    static func image(width: Int, height: Int, shift: Int = 0, checkerboard: Bool = false) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        if checkerboard {
            let cell = max(width, height) / 6
            for row in 0...(height / cell) {
                for column in 0...(width / cell) where (row + column).isMultiple(of: 2) {
                    context.setFillColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1)
                    context.fill(CGRect(x: column * cell, y: row * cell, width: cell, height: cell))
                }
            }
            return context.makeImage()
        }
        for band in 0..<16 {
            let gray = CGFloat(band) / 15
            context.setFillColor(red: gray, green: 0.4, blue: 1 - gray, alpha: 1)
            context.fill(CGRect(x: band * width / 16, y: 0, width: width / 16 + 1, height: height))
        }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: width / 3 + shift, y: height / 3, width: width / 4, height: height / 4))
        return context.makeImage()
    }

    @discardableResult
    static func write(
        _ image: CGImage, to url: URL, type: UTType,
        properties: [CFString: Any] = [:]
    ) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    /// JPEG with GPS, EXIF, TIFF and IPTC metadata plus an orientation tag (6 = rotated 90° CW).
    static func jpegWithMetadata(at url: URL, width: Int = 1600, height: Int = 1200, orientation: Int = 1) throws {
        guard let image = image(width: width, height: height) else { throw CocoaError(.fileWriteUnknown) }
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: gps,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Casa da Ana, Rua X 123"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 15"],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCity: "Ubatuba"],
        ]
        guard write(image, to: url, type: .jpeg, properties: properties) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// A real, valid JPEG above the pixel budget. Grayscale keeps the test cheap (56 MB to draw, tiny file).
    static func oversizedGrayJPEG(at url: URL, width: Int = 8000, height: Int = 7000) -> Bool {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let image = context.makeImage() else { return false }
        return write(image, to: url, type: .jpeg)
    }

    static func properties(of url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }
}
