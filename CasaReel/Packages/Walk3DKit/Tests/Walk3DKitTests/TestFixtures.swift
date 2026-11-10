import CoreGraphics
import Foundation

/// Builds test media on the fly so no binary fixtures live in the repo.
final class MediaFixtures {
    let directory = FileManager.default.temporaryDirectory.appending(path: "Walk3DKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A checkerboard shifted by `offset`, so every image has edges and differs from its neighbors.
    static func image(width: Int = 320, height: Int = 240, offset: Int = 0) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cell = 20
        for row in 0...(height / cell) {
            for column in 0...(width / cell) where (row + column).isMultiple(of: 2) {
                context.setFillColor(red: 0.9, green: 0.8, blue: 0.1, alpha: 1)
                context.fill(CGRect(x: column * cell + offset, y: row * cell, width: cell, height: cell))
            }
        }
        return context.makeImage()
    }
}
