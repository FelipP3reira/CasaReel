import CoreGraphics
import CoreImage
import Domain
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Quality, room, focus and faces for a prepared photo, entirely on the device.
/// Works on a ≤1024 px copy decoded with downsampling, so 40 photos never pile up in memory.
public final class PhotoAnalysisService: PhotoAnalyzing {
    /// Vision runs on this size; quality metrics on `qualitySize` (4× fewer pixels, same verdicts).
    static let analysisSize = 1024
    static let qualitySize = 512

    private let classifier: any RoomClassifying

    public init(classifier: any RoomClassifying = VisionRoomClassifier()) {
        self.classifier = classifier
    }

    public func analyze(_ photo: PreparedPhoto) async throws -> AnalysisResult {
        try Task.checkCancellation()
        guard
            let image = PhotoSanitizer.decode(photo.fileURL, maxPixelSize: Self.analysisSize),
            let gray = GrayImage(image, maxSide: Self.qualitySize)
        else { throw PhotoRejection.unreadable }

        let metrics = QualityMetrics.measure(gray)
        let score = QualityScorer.score(metrics)
        try Task.checkCancellation()
        let faces = FocusPlanner.faces(in: image)
        let focus = FocusPlanner.focus(in: image, keeping: faces)
        try Task.checkCancellation()
        let room = classifier.classify(image)

        return AnalysisResult(
            photoID: photo.id, qualityScore: score.overall, sharpness: score.sharpness,
            exposure: metrics.meanLuminance, noise: metrics.noiseSigma, warnings: score.warnings,
            room: room.room, roomConfidence: room.confidence, focus: focus, faces: faces
        )
    }

    public func blurFaces(in photo: PreparedPhoto, regions: [CGRect]) async throws -> PreparedPhoto {
        guard !regions.isEmpty else { return photo }
        try Task.checkCancellation()
        let output = photo.fileURL.deletingLastPathComponent().appending(path: "\(UUID().uuidString).jpg")
        guard
            let image = PhotoSanitizer.decode(photo.fileURL, maxPixelSize: max(photo.width, photo.height)),
            let blurred = FaceBlurrer.blur(image, regions: regions)
        else { throw PhotoRejection.unreadable }

        // Same metadata-free encoding as the sanitizer.
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoRejection.unreadable
        }
        CGImageDestinationAddImage(destination, blurred, [kCGImageDestinationLossyCompressionQuality: PhotoSanitizer.jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination), let hash = PerceptualHash.dHash(ofFileAt: output) else {
            try? FileManager.default.removeItem(at: output)
            throw PhotoRejection.unreadable
        }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: output.path)
        return PreparedPhoto(
            id: photo.id, fileURL: output, sha256: try FileHasher.sha256(ofFileAt: output),
            size: try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0,
            width: blurred.width, height: blurred.height, mimeType: .jpeg, perceptualHash: hash
        )
    }
}

/// Saliency and faces from Vision, converted to normalized rects with a top-left origin.
enum FocusPlanner {
    static let fullFrame = CGRect(x: 0, y: 0, width: 1, height: 1)

    static func faces(in image: CGImage) -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return [] }
        return (request.results ?? []).map { topLeft($0.boundingBox) }
    }

    /// Union of the salient objects, grown to include every face so pan/zoom never cuts one.
    static func focus(in image: CGImage, keeping faces: [CGRect]) -> CGRect {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        var salient: [CGRect] = []
        if (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil {
            salient = (request.results?.first?.salientObjects ?? []).map { topLeft($0.boundingBox) }
        }
        return union(salient + faces)
    }

    static func union(_ rects: [CGRect]) -> CGRect {
        guard let first = rects.first else { return fullFrame }
        return rects.dropFirst().reduce(first) { $0.union($1) }.intersection(fullFrame)
    }

    /// Vision uses a bottom-left origin; the app uses top-left.
    static func topLeft(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }
}

enum FaceBlurrer {
    /// Blurs each normalized (top-left) region, grown by 15% so hairlines and chins are covered.
    static func blur(_ image: CGImage, regions: [CGRect]) -> CGImage? {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let source = CIImage(cgImage: image)
        var result = source
        for region in regions {
            // Core Image uses a bottom-left origin in pixels.
            let pixels = CGRect(x: region.minX * width, y: (1 - region.maxY) * height, width: region.width * width, height: region.height * height)
                .insetBy(dx: -region.width * width * 0.15, dy: -region.height * height * 0.15)
                .intersection(source.extent)
            guard !pixels.isEmpty else { continue }
            let radius = max(pixels.width, pixels.height) * 0.12
            let blurred = source.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: pixels)
            result = blurred.composited(over: result)
        }
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(result, from: source.extent)
    }
}
