import Foundation
import simd

/// Decides which ARKit frames become training images.
///
/// Splat training needs views spread around the room with overlap, not 60 copies per second of the same
/// view: a frame is kept once the camera has moved or turned enough since the last kept one.
struct KeyframeSelector {
    var minDistance: Float = 0.12
    var minAngle: Float = 8 * .pi / 180
    /// Seconds; also lets the exposure settle between keyframes.
    var minInterval: Double = 0.2
    var maxKeyframes = CaptureManifest.maxKeyframes

    private(set) var count = 0
    private var last: (time: Double, position: SIMD3<Float>, forward: SIMD3<Float>)?

    var isFull: Bool { count >= maxKeyframes }

    /// Call only for frames with normal tracking. Returns `true` and records the frame when it is kept.
    mutating func keep(time: Double, position: SIMD3<Float>, forward: SIMD3<Float>) -> Bool {
        guard !isFull, position.allFinite, forward.allFinite else { return false }
        if let last {
            guard time - last.time >= minInterval else { return false }
            let moved = simd_distance(position, last.position) >= minDistance
            let turned = acos(min(max(simd_dot(simd_normalize(forward), last.forward), -1), 1)) >= minAngle
            guard moved || turned else { return false }
        }
        last = (time, position, simd_normalize(forward))
        count += 1
        return true
    }
}

/// ARKit's feature points, merged across frames. ARKit keeps refining a point under the same identifier,
/// so the latest position wins.
struct PointCloudAccumulator {
    static let maxPoints = 150_000

    private(set) var points: [UInt64: SIMD3<Float>] = [:]

    mutating func add(identifiers: [UInt64], positions: [SIMD3<Float>]) {
        for (identifier, position) in zip(identifiers, positions) where position.allFinite {
            guard points[identifier] != nil || points.count < Self.maxPoints else { continue }
            points[identifier] = position
        }
    }

    /// x, y, z per point as little-endian f32.
    func encoded() -> Data {
        var data = Data(capacity: points.count * 12)
        for position in points.values {
            for value in [position.x, position.y, position.z] {
                withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            }
        }
        return data
    }

    static func decode(_ data: Data) throws(SceneCaptureError) -> [SIMD3<Float>] {
        guard data.count.isMultiple(of: 12), data.count / 12 <= maxPoints else { throw .invalidCapture }
        return data.withUnsafeBytes { raw in
            (0..<(data.count / 12)).compactMap { index in
                func float(_ offset: Int) -> Float { Float(bitPattern: raw.loadUnaligned(fromByteOffset: index * 12 + offset, as: UInt32.self).littleEndian) }
                let point = SIMD3(float(0), float(4), float(8))
                return point.allFinite ? point : nil
            }
        }
    }
}

extension SIMD3 where Scalar == Float {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}
