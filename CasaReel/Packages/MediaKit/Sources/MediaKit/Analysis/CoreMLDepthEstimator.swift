import CoreGraphics
import CoreImage
import CoreML
import Domain
import Foundation
import Vision

/// Monocular depth on the device with Depth Anything V2 Small (Apple's Core ML conversion, Apache-2.0).
/// The model outputs relative inverse depth (larger = nearer), which matches `DepthEstimating`'s "white is near".
/// Nothing leaves the device. The ~24 MB model loads on first use, not at launch.
public final class CoreMLDepthEstimator: DepthEstimating, @unchecked Sendable {
    static let modelName = "DepthAnythingV2SmallF16P8"

    private let modelURL: URL?
    private let context = CIContext(options: [.cacheIntermediates: false])
    /// Guards `model` and serializes predictions (one Neural Engine request at a time is enough for rendering).
    private let lock = NSLock()
    private var model: VNCoreMLModel?
    private var loadFailed = false

    public init() {
        modelURL = Bundle.module.url(forResource: Self.modelName, withExtension: "mlmodelc")
    }

    public func depthMap(for image: CGImage) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let model = loadedModel() else { return nil }
        let request = VNCoreMLRequest(model: model)
        // The model takes a fixed 518×392 input; stretching keeps every pixel of the photo covered.
        request.imageCropAndScaleOption = .scaleFill
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            return nil
        }
        guard let buffer = (request.results?.first as? VNPixelBufferObservation)?.pixelBuffer else { return nil }
        return grayscale(from: CIImage(cvPixelBuffer: buffer))
    }

    private func loadedModel() -> VNCoreMLModel? {
        if let model { return model }
        guard !loadFailed, let modelURL else { return nil }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        do {
            let loaded = try VNCoreMLModel(for: MLModel(contentsOf: modelURL, configuration: configuration))
            model = loaded
            return loaded
        } catch {
            loadFailed = true
            return nil
        }
    }

    /// Reads the half-float map as floats and stretches it to the full 0–255 range.
    private func grayscale(from depth: CIImage) -> CGImage? {
        let width = Int(depth.extent.width), height = Int(depth.extent.height)
        guard width > 0, height > 0 else { return nil }
        var values = [Float](repeating: 0, count: width * height)
        context.render(depth, toBitmap: &values, rowBytes: width * MemoryLayout<Float>.size,
                       bounds: depth.extent, format: .Rf, colorSpace: nil)
        let bytes = Self.normalize(values)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// Min–max to 0–255; non-finite values count as farthest. A flat map becomes mid-gray (no parallax cue).
    static func normalize(_ values: [Float]) -> [UInt8] {
        let finite = values.filter(\.isFinite)
        guard let low = finite.min(), let high = finite.max() else { return [UInt8](repeating: 0, count: values.count) }
        let range = high - low
        guard range > .ulpOfOne else { return [UInt8](repeating: 128, count: values.count) }
        return values.map { value in
            guard value.isFinite else { return 0 }
            return UInt8(((value - low) / range * 255).rounded())
        }
    }
}
