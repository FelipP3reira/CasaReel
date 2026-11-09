import CoreGraphics
import CoreImage
import Domain
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MediaKit

/// Synthetic photos with a known property each.
enum AnalysisFixtures {
    static func detailed(width: Int = 1600, height: Int = 1200, brightness: CGFloat = 1) -> CGImage? {
        guard let context = rgbContext(width: width, height: height) else { return nil }
        let cell = 6
        for row in 0..<(height / cell) {
            for column in 0..<(width / cell) {
                let shade = (row + column).isMultiple(of: 2) ? 0.85 : 0.2
                context.setFillColor(red: shade * brightness, green: shade * brightness * 0.95, blue: shade * brightness * 0.9, alpha: 1)
                context.fill(CGRect(x: column * cell, y: row * cell, width: cell, height: cell))
            }
        }
        return context.makeImage()
    }

    static func flat(gray: CGFloat, width: Int = 1600, height: Int = 1200) -> CGImage? {
        guard let context = rgbContext(width: width, height: height) else { return nil }
        context.setFillColor(red: gray, green: gray, blue: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    static func blurred(_ image: CGImage, radius: Double = 12) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: input.extent)
        return CIContext().createCGImage(output, from: input.extent)
    }

    static func gray(_ width: Int, _ height: Int, _ value: (Int, Int) -> UInt8) -> GrayImage {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height { for x in 0..<width { pixels[y * width + x] = value(x, y) } }
        return GrayImage(width: width, height: height, pixels: pixels)
    }

    static func photo(_ image: CGImage, in directory: URL) throws -> PreparedPhoto {
        let url = directory.appending(path: "\(UUID().uuidString).jpg")
        guard Fixtures.write(image, to: url, type: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: 0.95]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return PreparedPhoto(fileURL: url, sha256: "", size: 0, width: image.width, height: image.height, mimeType: .jpeg, perceptualHash: 0)
    }

    private static func rgbContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    }
}

struct QualityMetricsTests {
    @Test func edgesRaiseLaplacianVariance() {
        let flat = AnalysisFixtures.gray(64, 64) { _, _ in 128 }
        let checker = AnalysisFixtures.gray(64, 64) { x, y in (x / 2 + y / 2).isMultiple(of: 2) ? 30 : 220 }
        #expect(QualityMetrics.measure(flat).laplacianVariance == 0)
        #expect(QualityMetrics.measure(checker).laplacianVariance > QualityScorer.blurThreshold * 10)
    }

    @Test func measuresLuminanceAndClipping() {
        let dark = QualityMetrics.measure(AnalysisFixtures.gray(32, 32) { _, _ in 5 })
        let bright = QualityMetrics.measure(AnalysisFixtures.gray(32, 32) { _, _ in 250 })
        #expect(dark.meanLuminance < 0.05)
        #expect(dark.darkFraction == 1)
        #expect(bright.meanLuminance > 0.95)
        #expect(bright.brightFraction == 1)
    }

    @Test func noiseEstimateIgnoresFlatAreasAndDetectsGrain() {
        var generator = SystemRandomNumberGenerator()
        let clean = QualityMetrics.measure(AnalysisFixtures.gray(128, 128) { _, _ in 120 })
        let grainy = QualityMetrics.measure(AnalysisFixtures.gray(128, 128) { _, _ in UInt8(120 + Int.random(in: -10...10, using: &generator)) })
        #expect(clean.noiseSigma == 0)
        #expect(grainy.noiseSigma > clean.noiseSigma)
    }

    @Test func scorerWarnsForEachProblem() {
        let good = QualityMetrics(laplacianVariance: 900, meanLuminance: 0.5, darkFraction: 0.05, brightFraction: 0.05, noiseSigma: 2)
        let bad = QualityMetrics(laplacianVariance: 10, meanLuminance: 0.1, darkFraction: 0.8, brightFraction: 0, noiseSigma: 20)
        let blown = QualityMetrics(laplacianVariance: 900, meanLuminance: 0.9, darkFraction: 0, brightFraction: 0.7, noiseSigma: 2)

        #expect(QualityScorer.score(good).warnings.isEmpty)
        #expect(QualityScorer.score(bad).warnings == [.blurry, .tooDark, .noisy])
        #expect(QualityScorer.score(blown).warnings == [.tooBright])
        #expect(QualityScorer.score(good).overall > QualityScorer.score(bad).overall)
        #expect((0...1).contains(QualityScorer.score(bad).overall))
    }
}

struct RoomMappingTests {
    @Test(arguments: [
        ([("kitchen", 0.8)], RoomType.kitchen),
        ([("bed", 0.4), ("pillow", 0.3)], .bedroom),
        ([("bathtub", 0.5)], .bathroom),
        ([("sofa", 0.6), ("interior_room", 0.9)], .livingRoom),
        ([("swimming_pool", 0.7)], .pool),
        ([("patio", 0.5)], .balcony),
        ([("house", 0.6), ("sky", 0.9)], .facade),
        ([("dog", 0.9)], .other),
        ([("kitchen", 0.08)], .other),
        ([], .other),
    ] as [([(String, Double)], RoomType)])
    func mapsVisionLabels(observations: [(String, Double)], expected: RoomType) {
        #expect(VisionRoomClassifier.room(for: observations.map { (identifier: $0.0, confidence: $0.1) }).room == expected)
    }

    @Test func strongestRoomWinsWhenLabelsDisagree() {
        let result = VisionRoomClassifier.room(for: [(identifier: "bed", confidence: 0.3), (identifier: "kitchen", confidence: 0.6)])
        #expect(result.room == .kitchen)
        #expect(result.confidence == 0.6)
    }
}

struct FocusPlannerTests {
    @Test func convertsVisionCoordinatesToTopLeft() {
        let converted = FocusPlanner.topLeft(CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.2))
        #expect(abs(converted.minY - 0.1) < 1e-9)
        #expect((converted.minX, converted.width, converted.height) == (0.1, 0.2, 0.2))
    }

    @Test func unionCoversAllRegionsAndStaysInFrame() {
        #expect(FocusPlanner.union([]) == FocusPlanner.fullFrame)
        let union = FocusPlanner.union([CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2), CGRect(x: 0.6, y: 0.5, width: 0.6, height: 0.6)])
        #expect(union == CGRect(x: 0.1, y: 0.1, width: 0.9, height: 0.9))
    }
}

private func fixture(_ image: CGImage?) throws -> CGImage {
    guard let image else { throw CocoaError(.fileWriteUnknown) }
    return image
}

final class PhotoAnalysisServiceTests {
    private let directory: URL
    private let service = PhotoAnalysisService()

    init() throws {
        directory = try Fixtures.directory()
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func blurredPhotoScoresBelowSharpOne() async throws {
        let sharpImage = try #require(AnalysisFixtures.detailed())
        let sharp = try await service.analyze(AnalysisFixtures.photo(sharpImage, in: directory))
        let blurredImage = try #require(AnalysisFixtures.blurred(sharpImage))
        let blurred = try await service.analyze(AnalysisFixtures.photo(blurredImage, in: directory))

        #expect(blurred.sharpness < sharp.sharpness)
        #expect(blurred.qualityScore < sharp.qualityScore)
        #expect(blurred.warnings.contains(.blurry))
        #expect(!sharp.warnings.contains(.blurry))
    }

    @Test func darkAndBrightPhotosAreFlagged() async throws {
        let darkImage = try #require(AnalysisFixtures.detailed(brightness: 0.12))
        let brightImage = try #require(AnalysisFixtures.flat(gray: 0.97))
        let normalImage = try #require(AnalysisFixtures.detailed())
        let dark = try await service.analyze(AnalysisFixtures.photo(darkImage, in: directory))
        let bright = try await service.analyze(AnalysisFixtures.photo(brightImage, in: directory))
        let normal = try await service.analyze(AnalysisFixtures.photo(normalImage, in: directory))

        #expect(dark.warnings.contains(.tooDark))
        #expect(bright.warnings.contains(.tooBright))
        #expect(dark.exposure < normal.exposure)
        #expect(bright.exposure > normal.exposure)
    }

    @Test func resultIsWellFormed() async throws {
        let photo = try AnalysisFixtures.photo(try fixture(AnalysisFixtures.detailed()), in: directory)
        let result = try await service.analyze(photo)

        #expect(result.photoID == photo.id)
        #expect((0...1).contains(result.qualityScore))
        #expect((0...1).contains(result.roomConfidence))
        #expect(FocusPlanner.fullFrame.contains(result.focus))
        #expect(RoomType.allCases.contains(result.room))
    }

    @Test func unreadablePhotoThrows() async {
        let missing = PreparedPhoto(fileURL: directory.appending(path: "nope.jpg"), sha256: "", size: 0, width: 0, height: 0, mimeType: .jpeg, perceptualHash: 0)
        await #expect(throws: PhotoRejection.unreadable) { try await self.service.analyze(missing) }
    }

    @Test func blurringChangesOnlyTheRegionAndKeepsNoMetadata() async throws {
        let image = try #require(AnalysisFixtures.detailed(width: 1600, height: 1200))
        let photo = try AnalysisFixtures.photo(image, in: directory)
        let region = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)

        let blurred = try await service.blurFaces(in: photo, regions: [region])

        #expect(blurred.id == photo.id)
        #expect(blurred.fileURL != photo.fileURL)
        #expect(blurred.sha256.count == 64)
        #expect(Fixtures.properties(of: blurred.fileURL)[kCGImagePropertyGPSDictionary] == nil)
        let beforeImage = try #require(PhotoSanitizer.decode(photo.fileURL, maxPixelSize: 1600))
        let afterImage = try #require(PhotoSanitizer.decode(blurred.fileURL, maxPixelSize: 1600))
        let before = try #require(GrayImage(beforeImage))
        let after = try #require(GrayImage(afterImage))
        func crop(_ image: GrayImage, x: Int, y: Int) -> GrayImage {
            AnalysisFixtures.gray(100, 100) { dx, dy in image.pixels[(y + dy) * image.width + x + dx] }
        }
        let inside = (QualityMetrics.measure(crop(before, x: 750, y: 550)), QualityMetrics.measure(crop(after, x: 750, y: 550)))
        let outside = (QualityMetrics.measure(crop(before, x: 50, y: 50)), QualityMetrics.measure(crop(after, x: 50, y: 50)))
        #expect(inside.1.laplacianVariance < inside.0.laplacianVariance / 4)
        #expect(outside.1.laplacianVariance > outside.0.laplacianVariance / 2)
    }

    @Test func blurWithoutRegionsReturnsSamePhoto() async throws {
        let photo = try AnalysisFixtures.photo(try fixture(AnalysisFixtures.flat(gray: 0.5)), in: directory)
        #expect(try await service.blurFaces(in: photo, regions: []) == photo)
    }

    @Test(.timeLimit(.minutes(3)))
    func analyzesFortyPhotosSequentially() async throws {
        let photo = try AnalysisFixtures.photo(try fixture(AnalysisFixtures.detailed()), in: directory)
        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            for _ in 0..<PhotoLimits.maximumCount {
                _ = try await service.analyze(photo)
            }
        }
        print("40 analyses took \(elapsed)")
        #expect(elapsed < .seconds(120))
    }
}
