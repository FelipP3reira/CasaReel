import CoreGraphics
import Foundation
import ImageIO
import simd

/// One training camera, in the exact layout of `View` in `TrainingShaders` (96 bytes).
struct TrainingView {
    static let tile = 16

    /// World→camera rows, translation in `w`.
    var r0: SIMD4<Float>, r1: SIMD4<Float>, r2: SIMD4<Float>
    /// fx, fy, cx, cy.
    var intrinsics: SIMD4<Float>
    /// width, height, tilesX, tilesY.
    var size: SIMD4<UInt32>
    /// rgb, and 1 / (3 · pixels) in `w`: the L1 loss is the mean over pixels and channels.
    var background: SIMD4<Float>

    init(camera: CapturedCamera, background: SIMD3<Float>) {
        let c2w = camera.cameraToWorld
        let rotation = simd_float3x3(SIMD3(c2w.columns.0.x, c2w.columns.0.y, c2w.columns.0.z),
                                     SIMD3(c2w.columns.1.x, c2w.columns.1.y, c2w.columns.1.z),
                                     SIMD3(c2w.columns.2.x, c2w.columns.2.y, c2w.columns.2.z)).transpose
        let translation = -(rotation * camera.position)
        // simd matrices are column major: row i of `rotation` is (columns.0[i], columns.1[i], columns.2[i]).
        func row(_ i: Int) -> SIMD4<Float> { SIMD4(rotation.columns.0[i], rotation.columns.1[i], rotation.columns.2[i], translation[i]) }
        r0 = row(0)
        r1 = row(1)
        r2 = row(2)
        intrinsics = SIMD4(camera.fx, camera.fy, camera.cx, camera.cy)
        let tilesX = (camera.width + Self.tile - 1) / Self.tile, tilesY = (camera.height + Self.tile - 1) / Self.tile
        size = SIMD4(UInt32(camera.width), UInt32(camera.height), UInt32(tilesX), UInt32(tilesY))
        self.background = SIMD4(background, 1 / Float(3 * camera.width * camera.height))
    }

    var width: Int { Int(size.x) }
    var height: Int { Int(size.y) }
    var tileCount: Int { Int(size.z * size.w) }

    var center: SIMD3<Float> {
        let rotation = simd_float3x3(rows: [SIMD3(r0.x, r0.y, r0.z), SIMD3(r1.x, r1.y, r1.z), SIMD3(r2.x, r2.y, r2.z)])
        return -(rotation.transpose * SIMD3(r0.w, r1.w, r2.w))
    }

    /// Pixel a world point lands on, or `nil` behind the camera or outside the image.
    func project(_ point: SIMD3<Float>) -> SIMD2<Float>? {
        let p = SIMD4(point, 1)
        let camera = SIMD3(simd_dot(r0, p), simd_dot(r1, p), simd_dot(r2, p))
        guard camera.z > 0.05 else { return nil }
        let pixel = SIMD2(intrinsics.x * camera.x / camera.z + intrinsics.z, intrinsics.y * camera.y / camera.z + intrinsics.w)
        guard pixel.x >= 0, pixel.y >= 0, pixel.x < Float(width), pixel.y < Float(height) else { return nil }
        return pixel
    }
}

/// A keyframe decoded to RGBA8 at training resolution.
struct TrainingImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Decodes and resizes to exactly `width` × `height` (the intrinsics were scaled to that size).
    init?(contentsOf url: URL, width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(width, height),
              ] as CFDictionary)
        else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, pixels: pixels)
    }

    func color(at pixel: SIMD2<Float>) -> SIMD3<Float>? {
        let x = Int(pixel.x), y = Int(pixel.y)
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let base = (y * width + x) * 4
        return SIMD3(Float(pixels[base]), Float(pixels[base + 1]), Float(pixels[base + 2])) / 255
    }
}
