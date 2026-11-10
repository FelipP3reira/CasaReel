import CoreGraphics
import Foundation

/// Cheap per-image measurements on a tiny grayscale copy: how sharp it is and a perceptual fingerprint.
enum ImageMetrics {
    /// Variance of the Laplacian on a 128-px-wide grayscale copy; blurry frames score low.
    static func sharpness(of image: CGImage) -> Double {
        guard let (pixels, width, height) = grayscale(image, width: 128) else { return 0 }
        guard width > 2, height > 2 else { return 0 }
        var sum = 0.0, sumSquares = 0.0, count = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = Double(pixels[y * width + x])
                let laplacian = Double(pixels[(y - 1) * width + x]) + Double(pixels[(y + 1) * width + x])
                    + Double(pixels[y * width + x - 1]) + Double(pixels[y * width + x + 1]) - 4 * center
                sum += laplacian
                sumSquares += laplacian * laplacian
                count += 1
            }
        }
        let mean = sum / count
        return sumSquares / count - mean * mean
    }

    /// 64-bit difference hash: each bit says whether a pixel is brighter than its right neighbor (9×8 grid).
    static func differenceHash(of image: CGImage) -> UInt64 {
        guard let (pixels, width, _) = grayscale(image, width: 9, height: 8) else { return 0 }
        var hash: UInt64 = 0
        for y in 0..<8 {
            for x in 0..<8 where pixels[y * width + x] > pixels[y * width + x + 1] {
                hash |= 1 << UInt64(y * 8 + x)
            }
        }
        return hash
    }

    static func distance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    private static func grayscale(_ image: CGImage, width: Int, height: Int? = nil) -> ([UInt8], Int, Int)? {
        let height = height ?? max(1, Int((Double(image.height) / Double(max(image.width, 1)) * Double(width)).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (pixels, width, height) : nil
    }
}
