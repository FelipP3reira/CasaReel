@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Walk3DKit

/// Builds test media on the fly so no binary fixtures live in the repo.
final class MediaFixtures {
    let directory = FileManager.default.temporaryDirectory.appending(path: "Walk3DKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A checkerboard shifted by `offset`, so every image has edges (sharp) and differs from its neighbors.
    static func image(width: Int = 320, height: Int = 240, offset: Int = 0, blurred: Bool = false) -> CGImage? {
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
        guard let sharp = context.makeImage() else { return nil }
        guard blurred, let small = CGContext(data: nil, width: width / 16, height: height / 16, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return sharp }
        small.interpolationQuality = .high
        small.draw(sharp, in: CGRect(x: 0, y: 0, width: width / 16, height: height / 16))
        guard let tiny = small.makeImage() else { return nil }
        context.interpolationQuality = .high
        context.draw(tiny, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// A JPEG with GPS metadata, to prove it does not survive the export.
    func photo(offset: Int) throws -> URL {
        let url = directory.appending(path: "photo-\(offset).jpg")
        let image = try #require(Self.image(offset: offset))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 23.43, kCGImagePropertyGPSLatitudeRef: "S"]
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// `seconds` of 30 fps video where the checkerboard slides, like a camera panning.
    func video(seconds: Int) async throws -> URL {
        let url = directory.appending(path: "video.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(seconds * 30) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            let pool = try #require(adaptor.pixelBufferPool)
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: 320, height: 240, bitsPerComponent: 8,
                                    bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            if let image = Self.image(offset: frame * 2) { context?.draw(image, in: CGRect(x: 0, y: 0, width: 320, height: 240)) }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }
}

struct ImageMetricsTests {
    @Test func blurLowersSharpness() throws {
        let sharp = try #require(MediaFixtures.image())
        let blurred = try #require(MediaFixtures.image(blurred: true))
        #expect(ImageMetrics.sharpness(of: sharp) > ImageMetrics.sharpness(of: blurred) * 4)
    }

    @Test func hashIsStableForTheSameViewAndChangesWithTheView() throws {
        let a = try #require(MediaFixtures.image()), b = try #require(MediaFixtures.image())
        let moved = try #require(MediaFixtures.image(offset: 10))
        #expect(ImageMetrics.distance(ImageMetrics.differenceHash(of: a), ImageMetrics.differenceHash(of: b)) == 0)
        #expect(ImageMetrics.distance(ImageMetrics.differenceHash(of: a), ImageMetrics.differenceHash(of: moved)) > 3)
    }
}

struct FrameSelectorTests {
    private func run(_ candidates: [FrameSelector.Candidate], window: Double) -> [Double] {
        var selector = FrameSelector(window: window)
        var picks: [Double] = []
        for candidate in candidates { if let pick = selector.add(candidate) { picks.append(pick.time) } }
        if let last = selector.finish() { picks.append(last.time) }
        return picks
    }

    @Test func keepsTheSharpestFramePerWindow() {
        let candidates = [
            FrameSelector.Candidate(time: 0.1, sharpness: 10, hash: 0x0F), .init(time: 0.4, sharpness: 50, hash: 0xF0),
            .init(time: 1.1, sharpness: 60, hash: 0xFF00), .init(time: 1.6, sharpness: 20, hash: 0xFF),
        ]
        #expect(run(candidates, window: 1) == [0.4, 1.1])
    }

    @Test func dropsStandingStillAndBlurredFrames() {
        let candidates = [
            FrameSelector.Candidate(time: 0.5, sharpness: 100, hash: 0xFF),
            .init(time: 1.5, sharpness: 100, hash: 0xFE),         // same view: 1 bit apart
            .init(time: 2.5, sharpness: 5, hash: 0xFF_0000),      // motion blur
            .init(time: 3.5, sharpness: 90, hash: 0xFF_0000_0000),
        ]
        #expect(run(candidates, window: 1) == [0.5, 3.5])
    }

    @Test func windowSpreadsTheFrameBudgetOverAllVideos() {
        #expect(FrameSelector.window(totalDuration: 400, maxFrames: 200) == 2)
        #expect(FrameSelector.window(totalDuration: 30, maxFrames: 200) == 0.5)
        #expect(FrameSelector.window(totalDuration: 0, maxFrames: 200) == 0.5)
    }
}

struct SceneArchiveTests {
    @Test func extractsOnlyTheRequestedRegularFiles() throws {
        let fixtures = try MediaFixtures()
        let source = fixtures.directory.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source.appending(path: "nested"), withIntermediateDirectories: true)
        try Data("splat".utf8).write(to: source.appending(path: "scene.splat"))
        try Data("{}".utf8).write(to: source.appending(path: "path.json"))
        try Data("x".utf8).write(to: source.appending(path: "nested/path.json"))
        try Data("x".utf8).write(to: source.appending(path: "extra.sh"))
        let archive = fixtures.directory.appending(path: "result.aar")
        try SceneArchive.write(directory: source, to: archive)

        let output = fixtures.directory.appending(path: "output", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let files = try SceneArchive.extract(["scene.splat", "path.json"], from: archive, to: output)
        let splat = try #require(files["scene.splat"]), path = try #require(files["path.json"])
        #expect(try Data(contentsOf: splat) == Data("splat".utf8))
        #expect(try Data(contentsOf: path) == Data("{}".utf8))
        #expect(!FileManager.default.fileExists(atPath: output.appending(path: "extra.sh").path))
        #expect(!FileManager.default.fileExists(atPath: output.appending(path: "nested").path))
    }

    @Test func missingEntryOrGarbageIsAnError() throws {
        let fixtures = try MediaFixtures()
        let garbage = fixtures.directory.appending(path: "garbage.aar")
        try Data("not an archive".utf8).write(to: garbage)
        #expect(throws: SceneArchive.Failure.self) { try SceneArchive.extract(["scene.splat"], from: garbage, to: fixtures.directory) }
    }
}

struct SceneExporterTests {
    @Test func exportsCleanPhotosAndVideoFramesIntoAnArchive() async throws {
        let fixtures = try MediaFixtures()
        let photos = try (0..<12).map { try fixtures.photo(offset: $0 * 7) }
        let video = try await fixtures.video(seconds: 6)
        let exporter = SceneExporter(workDirectory: fixtures.directory.appending(path: "work"))
        var result: SceneExportResult?
        var lastProgress = 0.0
        for try await event in exporter.export(photos: photos, videos: [video]) {
            switch event {
            case .progress(let value):
                #expect(value >= lastProgress - 1e-9)
                lastProgress = value
            case .finished(let finished): result = finished
            }
        }
        let exported = try #require(result)
        #expect(exported.photoCount == 12)
        #expect((8...12).contains(exported.frameCount), "about two frames per second of a 6 s video, got \(exported.frameCount)")

        // Unpack everything and check no GPS survived.
        let output = fixtures.directory.appending(path: "unpacked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let files = try SceneArchive.extract(["manifest.json"], from: exported.archiveURL, to: output)
        let manifestURL = try #require(files["manifest.json"])
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        #expect(manifest?["photos"] as? Int == 12)
        let photo = try SceneArchive.extract(["images/photos/photo_001.jpg"], from: exported.archiveURL, to: output)
        let photoURL = try #require(photo["images/photos/photo_001.jpg"])
        let source = try #require(CGImageSourceCreateWithURL(photoURL as CFURL, nil))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        #expect(properties?[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func tooFewImagesIsRejected() async throws {
        let fixtures = try MediaFixtures()
        let photos = try (0..<3).map { try fixtures.photo(offset: $0) }
        let exporter = SceneExporter(workDirectory: fixtures.directory.appending(path: "work"))
        await #expect(throws: SceneExportError.notEnoughImages(found: 3)) {
            for try await _ in exporter.export(photos: photos, videos: []) {}
        }
        await #expect(throws: SceneExportError.noMedia) {
            for try await _ in exporter.export(photos: [], videos: []) {}
        }
    }
}
