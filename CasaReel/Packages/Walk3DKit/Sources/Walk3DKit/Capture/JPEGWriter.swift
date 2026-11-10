import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum JPEGWriter {
    static let quality = 0.92

    /// Pixels only: no metadata dictionary is passed, so no EXIF or GPS can end up in the file.
    static func write(_ image: CGImage, to url: URL) throws(SceneCaptureError) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw .writeFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw .writeFailed }
    }
}
