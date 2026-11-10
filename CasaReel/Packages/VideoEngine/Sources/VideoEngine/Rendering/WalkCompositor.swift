import CoreGraphics
import CoreImage
import Domain
import Foundation

/// The "walk" look: a 2.5D dolly into a single photo, plus the walk-through transition between photos.
///
/// The photo is sliced into depth bands. Moving a camera forward makes near things grow faster than far ones
/// (they move away from the vanishing point in proportion to 1/distance), so each band is zoomed about the
/// center by an amount that rises with its nearness. Bands are drawn far to near and the farthest one is the
/// whole photo, so a nearer band only ever expands over what is behind it and no hole can open.
enum WalkCompositor {
    static let layerCount = 4
    /// How sharply a band's mask goes from 0 to 1 around its depth threshold (soft edges hide the cut).
    static let maskSteepness: CGFloat = 10

    /// - Parameters:
    ///   - photo: the photo already cropped and scaled into output coordinates (clamped, so zooming never shows an edge).
    ///   - depth: the depth map in the same coordinates (white = near).
    ///   - progress: eased scene progress, 0–1.
    ///   - parallax: extra zoom of the nearest band at `progress` 1.
    static func compose(photo: CIImage, depth: CIImage, progress: Double, parallax: Double, extent: CGRect) -> CIImage {
        let center = CGPoint(x: extent.midX, y: extent.midY)
        func transform(band: Int) -> CGAffineTransform {
            let nearness = (Double(band) + 0.5) / Double(layerCount)
            return zoom(1 + parallax * progress * nearness, about: center)
        }
        var image = photo.transformed(by: transform(band: 0)).cropped(to: extent)
        for band in 1..<layerCount {
            let threshold = CGFloat(band) / CGFloat(layerCount)
            let mask = bandMask(depth, threshold: threshold).transformed(by: transform(band: band))
            image = photo.transformed(by: transform(band: band))
                .applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask])
                .cropped(to: extent)
        }
        return image
    }

    /// 1 where depth ≥ threshold (nearer), 0 where it is farther, with a soft ramp in between.
    static func bandMask(_ depth: CIImage, threshold: CGFloat) -> CIImage {
        let gain = CIVector(x: maskSteepness, y: 0, z: 0, w: 0)
        let bias = 0.5 - maskSteepness * threshold
        return depth
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": gain, "inputGVector": gain, "inputBVector": gain,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
            ])
            .applyingFilter("CIColorClamp")
    }

    /// Keeps pushing into the outgoing photo (with a zoom blur, like a quick step forward)
    /// while the incoming one settles from a slight zoom, already moving.
    static func walkThrough(_ outgoing: CIImage, _ incoming: CIImage, mix: Double, extent: CGRect) -> CIImage {
        let center = CGPoint(x: extent.midX, y: extent.midY)
        let eased = TemplateSpec.Easing.easeInOut.apply(mix)
        let push = outgoing.clampedToExtent()
            .transformed(by: zoom(1 + 0.3 * mix, about: center))
            .applyingFilter("CIZoomBlur", parameters: [kCIInputCenterKey: CIVector(cgPoint: center), kCIInputAmountKey: 20 * mix])
            .cropped(to: extent)
        let arrive = incoming.clampedToExtent()
            .transformed(by: zoom(1.15 - 0.15 * eased, about: center))
            .cropped(to: extent)
        return push.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": arrive, "inputTime": eased])
    }

    /// Depth from the estimator, stretched over the photo and slightly softened so band edges don't look cut out.
    /// The map is read as raw values (no color management) so 50 % gray means half the depth range.
    static func depth(from map: CGImage, over photoExtent: CGRect) -> CIImage {
        let image = CIImage(cgImage: map, options: [.colorSpace: NSNull()])
        let scale = CGAffineTransform(scaleX: photoExtent.width / image.extent.width, y: photoExtent.height / image.extent.height)
        let radius = max(photoExtent.width, photoExtent.height) * 0.004
        return image.transformed(by: scale)
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: photoExtent)
    }

    /// Used when no depth model is available: a typical room seen from its doorway. The point the camera
    /// heads to is farthest, everything grows nearer toward the edges, and the floor (bottom) is nearest.
    /// - Parameter vanishingPoint: normalized, top-left origin (like the crop rects).
    static func fallbackDepth(over photoExtent: CGRect, vanishingPoint: CGPoint) -> CIImage {
        let diagonal = hypot(photoExtent.width, photoExtent.height)
        let center = CIVector(x: photoExtent.minX + vanishingPoint.x * photoExtent.width,
                              y: photoExtent.minY + (1 - vanishingPoint.y) * photoExtent.height)
        let room = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": center, "inputRadius0": diagonal * 0.05, "inputRadius1": diagonal * 0.6,
            "inputColor0": CIColor.black, "inputColor1": CIColor.white,
        ])?.outputImage
        let floor = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: photoExtent.midX, y: photoExtent.minY),
            "inputPoint1": CIVector(x: photoExtent.midX, y: photoExtent.minY + photoExtent.height * 0.45),
            "inputColor0": CIColor.white, "inputColor1": CIColor.black,
        ])?.outputImage
        let gray = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
        guard let room, let floor else { return gray.cropped(to: photoExtent) }
        return floor.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: room]).cropped(to: photoExtent)
    }

    static func zoom(_ scale: Double, about center: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: -center.x, y: -center.y)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }
}
