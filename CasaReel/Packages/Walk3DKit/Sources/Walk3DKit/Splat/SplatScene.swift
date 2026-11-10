import Foundation
import simd

public enum Walk3DImportError: Error, Sendable, Equatable {
    /// Not the `.aar` produced by `walk3d.sh`, or it is missing `scene.splat` / `path.json`.
    case invalidPackage
    case invalidScene
    case invalidPath
    case tooLarge
}

/// The Gaussians of a scene, as written by `tools/walk3d/convert.py` (32 bytes each, little endian):
/// position 3×f32 · scale 3×f32 · RGBA 4×u8 · rotation (w, x, y, z) 4×u8 mapped from −1…1.
struct SplatScene {
    static let recordSize = 32
    static let maxCount = 3_000_000

    /// Per Gaussian, in the layout the Metal shader reads (see `SplatShaders.source`).
    struct GPUSplat {
        var position: (Float, Float, Float)
        /// Upper triangle of the 3D covariance: xx, xy, xz, yy, yz, zz.
        var covariance: (Float, Float, Float, Float, Float, Float)
        /// RGBA8, red in the lowest byte.
        var color: UInt32
    }

    let splats: [GPUSplat]

    var count: Int { splats.count }

    init(splats: [GPUSplat]) {
        self.splats = splats
    }

    init(contentsOf url: URL) throws(Walk3DImportError) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw .invalidScene }
        try self.init(data: data)
    }

    init(data: Data) throws(Walk3DImportError) {
        guard !data.isEmpty, data.count.isMultiple(of: Self.recordSize) else { throw .invalidScene }
        let count = data.count / Self.recordSize
        guard count <= Self.maxCount else { throw .tooLarge }
        var splats: [GPUSplat] = []
        splats.reserveCapacity(count)
        data.withUnsafeBytes { raw in
            for index in 0..<count {
                let base = index * Self.recordSize
                func float(_ offset: Int) -> Float { Float(bitPattern: raw.loadUnaligned(fromByteOffset: base + offset, as: UInt32.self).littleEndian) }
                func byte(_ offset: Int) -> UInt8 { raw[base + offset] }
                let position = SIMD3(float(0), float(4), float(8))
                let scale = SIMD3(float(12), float(16), float(20))
                // Hostile or broken values are dropped rather than sent to the GPU.
                guard position.allFinite, scale.allFinite, scale.min() >= 0 else { continue }
                let rotation = simd_quatf(
                    ix: (Float(byte(29)) - 128) / 128, iy: (Float(byte(30)) - 128) / 128,
                    iz: (Float(byte(31)) - 128) / 128, r: (Float(byte(28)) - 128) / 128
                )
                let color = UInt32(byte(24)) | UInt32(byte(25)) << 8 | UInt32(byte(26)) << 16 | UInt32(byte(27)) << 24
                splats.append(GPUSplat(position: (position.x, position.y, position.z),
                                       covariance: Self.covariance(scale: scale, rotation: rotation), color: color))
            }
        }
        guard !splats.isEmpty else { throw .invalidScene }
        self.splats = splats
    }

    /// Σ = R S Sᵀ Rᵀ, stored as its upper triangle.
    static func covariance(scale: SIMD3<Float>, rotation: simd_quatf) -> (Float, Float, Float, Float, Float, Float) {
        let length = simd_length(rotation.vector)
        let unit = length > 0 ? simd_quatf(vector: rotation.vector / length) : simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        let m = simd_float3x3(unit) * simd_float3x3(diagonal: scale)
        let sigma = m * m.transpose
        return (sigma[0][0], sigma[1][0], sigma[2][0], sigma[1][1], sigma[2][1], sigma[2][2])
    }
}
