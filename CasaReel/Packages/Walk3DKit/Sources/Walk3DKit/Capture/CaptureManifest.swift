import Foundation
import simd

public enum SceneCaptureError: Error, Sendable, Equatable {
    /// The device has no world tracking (the simulator, for one).
    case unsupported
    /// Fewer than `CaptureManifest.minKeyframes`: the 3D would not hold together.
    case notEnoughKeyframes(found: Int)
    case insufficientStorage
    case writeFailed
    case invalidCapture
}

/// Pinhole camera of one keyframe. Axes follow the OpenCV camera convention: x right, y down, z forward.
public struct CapturedCamera: Sendable, Equatable {
    public var fx: Float, fy: Float, cx: Float, cy: Float
    public var width: Int, height: Int
    public var cameraToWorld: simd_float4x4

    public var position: SIMD3<Float> { SIMD3(cameraToWorld.columns.3.x, cameraToWorld.columns.3.y, cameraToWorld.columns.3.z) }
    public var forward: SIMD3<Float> { simd_normalize(SIMD3(cameraToWorld.columns.2.x, cameraToWorld.columns.2.y, cameraToWorld.columns.2.z)) }

    /// ARKit's camera looks along −z with y up; OpenCV's looks along +z with y down: flip both axes.
    static func openCVCameraToWorld(arkit transform: simd_float4x4) -> simd_float4x4 {
        transform * simd_float4x4(diagonal: SIMD4(1, -1, -1, 1))
    }

    /// Intrinsics after resizing the image by `factor`, keeping pixel centers aligned.
    func scaled(by factor: Float, width: Int, height: Int) -> CapturedCamera {
        CapturedCamera(fx: fx * factor, fy: fy * factor, cx: (cx + 0.5) * factor - 0.5, cy: (cy + 0.5) * factor - 0.5,
                       width: width, height: height, cameraToWorld: cameraToWorld)
    }
}

/// `capture.json`: what the on-device trainer reads. Images live next to it in `frames/`,
/// the ARKit feature points in `points.bin` (x, y, z as little-endian f32).
struct CaptureManifest: Codable, Equatable {
    static let format = "casareel-walk3d-capture"
    static let minKeyframes = 20
    static let maxKeyframes = 240

    struct Frame: Codable, Equatable {
        let image: String
        let fx: Float, fy: Float, cx: Float, cy: Float
        let width: Int, height: Int
        /// Camera-to-world, column major.
        let cameraToWorld: [Float]
    }

    var format = Self.format
    var version = 1
    let frames: [Frame]
    let pointCount: Int

    init(frames: [Frame], pointCount: Int) {
        self.frames = frames
        self.pointCount = pointCount
    }

    static func frame(image: String, camera: CapturedCamera) -> Frame {
        let m = camera.cameraToWorld
        let columns = [m.columns.0, m.columns.1, m.columns.2, m.columns.3]
        return Frame(image: image, fx: camera.fx, fy: camera.fy, cx: camera.cx, cy: camera.cy,
                     width: camera.width, height: camera.height, cameraToWorld: columns.flatMap { [$0.x, $0.y, $0.z, $0.w] })
    }

    /// The capture is written by the app, but still read defensively: a broken file must not reach the GPU.
    static func load(from data: Data) throws(SceneCaptureError) -> CaptureManifest {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let manifest = try? decoder.decode(CaptureManifest.self, from: data), manifest.format == format, manifest.version == 1,
              (minKeyframes...maxKeyframes).contains(manifest.frames.count), manifest.pointCount >= 0,
              manifest.frames.allSatisfy(\.isValid)
        else { throw .invalidCapture }
        return manifest
    }

    func encoded() throws(SceneCaptureError) -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { throw .writeFailed }
        return data
    }
}

extension CaptureManifest.Frame {
    var isValid: Bool {
        !image.contains("/") && !image.contains("..") && image.hasSuffix(".jpg")
            && (16...4096).contains(width) && (16...4096).contains(height)
            && fx > 0 && fy > 0 && cameraToWorld.count == 16
            && ([fx, fy, cx, cy] + cameraToWorld).allSatisfy(\.isFinite)
    }

    var camera: CapturedCamera {
        let c = cameraToWorld
        let matrix = simd_float4x4(SIMD4(c[0], c[1], c[2], c[3]), SIMD4(c[4], c[5], c[6], c[7]),
                                   SIMD4(c[8], c[9], c[10], c[11]), SIMD4(c[12], c[13], c[14], c[15]))
        return CapturedCamera(fx: fx, fy: fy, cx: cx, cy: cy, width: width, height: height, cameraToWorld: matrix)
    }
}
