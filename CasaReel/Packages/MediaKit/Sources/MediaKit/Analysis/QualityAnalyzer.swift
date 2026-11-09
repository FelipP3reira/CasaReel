import CoreGraphics
import Domain
import Foundation

/// 8-bit grayscale copy of an image, used for the quality metrics.
struct GrayImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height, "pixel count must match dimensions")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Draws `image` in grayscale, scaled down so the longer side is at most `maxSide`.
    init?(_ image: CGImage, maxSide: Int = .max) {
        let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
        let width = Int((Double(image.width) * scale).rounded()), height = Int((Double(image.height) * scale).rounded())
        guard width >= 3, height >= 3 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, pixels: pixels)
    }
}

/// Raw measurements on a 0–255 grayscale image.
struct QualityMetrics: Equatable {
    /// Variance of the 3×3 Laplacian: low means few sharp edges (blur).
    let laplacianVariance: Double
    /// Mean luminance 0–1.
    let meanLuminance: Double
    let darkFraction: Double
    let brightFraction: Double
    /// Immerkær noise estimate (σ), computed on flat areas only so texture isn't mistaken for noise.
    let noiseSigma: Double

    static func measure(_ image: GrayImage) -> QualityMetrics {
        let width = image.width, height = image.height
        var lapSum = 0.0, lapSquares = 0.0
        var noiseSum = 0.0, noiseCount = 0
        var luminanceSum = 0, dark = 0, bright = 0

        image.pixels.withUnsafeBufferPointer { p in
            for value in p {
                luminanceSum += Int(value)
                if value < 20 { dark += 1 } else if value > 235 { bright += 1 }
            }
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let i = y * width + x
                    let c = Int(p[i]), n = Int(p[i - width]), s = Int(p[i + width]), w = Int(p[i - 1]), e = Int(p[i + 1])
                    let laplacian = Double(n + s + w + e - 4 * c)
                    lapSum += laplacian
                    lapSquares += laplacian * laplacian

                    // Skip edges: the noise kernel also responds to real detail.
                    guard abs(e - w) + abs(s - n) < 24 else { continue }
                    let nw = Int(p[i - width - 1]), ne = Int(p[i - width + 1]), sw = Int(p[i + width - 1]), se = Int(p[i + width + 1])
                    noiseSum += Double(abs(nw + ne + sw + se - 2 * (n + s + w + e) + 4 * c))
                    noiseCount += 1
                }
            }
        }

        let interior = Double((width - 2) * (height - 2))
        let mean = lapSum / interior
        let total = Double(width * height)
        return QualityMetrics(
            laplacianVariance: max(0, lapSquares / interior - mean * mean),
            meanLuminance: Double(luminanceSum) / total / 255,
            darkFraction: Double(dark) / total,
            brightFraction: Double(bright) / total,
            noiseSigma: noiseCount > 0 ? noiseSum * (Double.pi / 2).squareRoot() / (6 * Double(noiseCount)) : 0
        )
    }
}

/// Turns metrics into 0–1 scores and warnings. Thresholds assume the ≤512 px quality copy.
enum QualityScorer {
    static let blurThreshold = 60.0
    static let noiseThreshold = 10.0

    struct Score: Equatable {
        let overall: Double
        let sharpness: Double
        let warnings: [QualityWarning]
    }

    static func score(_ metrics: QualityMetrics) -> Score {
        let sharpness = metrics.laplacianVariance / (metrics.laplacianVariance + 150)
        let exposure = clamp(
            1 - abs(metrics.meanLuminance - 0.5) * 1.6
                - max(0, metrics.darkFraction - 0.3) - max(0, metrics.brightFraction - 0.3)
        )
        let noise = 1 - clamp((metrics.noiseSigma - 3) / 12)

        var warnings: [QualityWarning] = []
        if metrics.laplacianVariance < blurThreshold { warnings.append(.blurry) }
        if metrics.meanLuminance < 0.22 || metrics.darkFraction > 0.6 { warnings.append(.tooDark) }
        if metrics.meanLuminance > 0.82 || metrics.brightFraction > 0.5 { warnings.append(.tooBright) }
        if metrics.noiseSigma > noiseThreshold { warnings.append(.noisy) }

        return Score(overall: clamp(0.5 * sharpness + 0.35 * exposure + 0.15 * noise), sharpness: sharpness, warnings: warnings)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
