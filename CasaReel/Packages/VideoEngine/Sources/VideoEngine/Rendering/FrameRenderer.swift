import CoreGraphics
import CoreImage
import Domain
import Foundation
import ImageIO
import UIKit

/// Text drawn into images once per render. Strings are only ever drawn as plain text.
enum OverlayFactory {
    static let maxCaptionLength = 60
    static let maxTitleLength = 80

    static func caption(_ text: String, outputWidth: CGFloat) -> CIImage? {
        label(String(text.prefix(maxCaptionLength)), fontSize: outputWidth * 0.045, weight: .semibold, padding: outputWidth * 0.02, background: 0.45)
    }

    static func title(_ text: String, outputWidth: CGFloat) -> CIImage? {
        label(String(text.prefix(maxTitleLength)), fontSize: outputWidth * 0.07, weight: .bold, padding: outputWidth * 0.03, background: 0.35)
    }

    static func watermark(outputWidth: CGFloat) -> CIImage? {
        label("CasaReel", fontSize: outputWidth * 0.035, weight: .heavy, padding: outputWidth * 0.012, background: 0.25)
    }

    private static func label(_ text: String, fontSize: CGFloat, weight: UIFont.Weight, padding: CGFloat, background: CGFloat) -> CIImage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard !trimmed.isEmpty else { return nil }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: UIColor.white,
        ]
        let string = NSAttributedString(string: trimmed, attributes: attributes)
        let textSize = string.boundingRect(with: CGSize(width: 4000, height: fontSize * 2), options: [.usesLineFragmentOrigin], context: nil).integral.size
        let size = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.withAlphaComponent(background).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: padding).fill()
            string.draw(at: CGPoint(x: padding, y: padding))
        }
        return image.cgImage.map { CIImage(cgImage: $0) }
    }
}

/// Draws the frame at a given time: photos with their motion, transitions, captions and watermark.
/// Only the photos on screen are decoded (at most two), downsampled to what the zoom needs.
final class FrameRenderer {
    let outputSize: CGSize
    let context: CIContext
    private let timeline: SceneTimeline
    private let photoURLs: [URL]
    private let captions: [Int: CIImage]
    private let title: CIImage?
    private let closing: CIImage?
    private let watermark: CIImage?
    private let watermarkPosition: TemplateSpec.Watermark.Position
    private var cache: [Int: CIImage] = [:]

    static let fadeMs = 400.0
    static let titleMs = 2_500.0

    init(
        timeline: SceneTimeline, photoURLs: [URL], outputSize: CGSize, context: CIContext,
        title: String?, closingText: String? = nil, watermark: Bool, watermarkPosition: TemplateSpec.Watermark.Position
    ) {
        self.timeline = timeline
        self.photoURLs = photoURLs
        self.outputSize = outputSize
        self.context = context
        self.watermarkPosition = watermarkPosition
        captions = Dictionary(uniqueKeysWithValues: timeline.entries.enumerated().compactMap { index, entry in
            entry.caption.flatMap { OverlayFactory.caption($0, outputWidth: outputSize.width) }.map { (index, $0) }
        })
        self.title = title.flatMap { OverlayFactory.title($0, outputWidth: outputSize.width) }
        closing = closingText.flatMap { OverlayFactory.title($0, outputWidth: outputSize.width) }
        self.watermark = watermark ? OverlayFactory.watermark(outputWidth: outputSize.width) : nil
    }

    var extent: CGRect { CGRect(origin: .zero, size: outputSize) }

    func image(atMs timeMs: Int) throws(RenderError) -> CIImage {
        let black = CIImage(color: .black).cropped(to: extent)
        guard let frame = timeline.frame(at: timeMs) else { return black }
        var image: CIImage
        var captionEntries: [(Int, Double)] = []
        switch frame {
        case .single(let index, let progress):
            image = try photoLayer(index, progress: progress)
            captionEntries = [(index, 1)]
        case .transition(let from, let to, let fromProgress, let toProgress, let mix, let kind):
            let outgoing = try photoLayer(from, progress: fromProgress)
            let incoming = try photoLayer(to, progress: toProgress)
            image = Self.blend(outgoing, incoming, mix: mix, kind: kind, extent: extent)
            captionEntries = [(from, 1 - mix), (to, mix)]
            cache = cache.filter { [from, to].contains($0.key) }
        }
        for (index, weight) in captionEntries {
            guard let caption = captions[index] else { continue }
            let entry = timeline.entries[index]
            let alpha = weight * Self.fade(timeMs - entry.startMs, total: entry.durationMs)
            image = Self.place(caption, alpha: alpha, at: CGPoint(x: outputSize.width * 0.06, y: outputSize.height * 0.08)).composited(over: image)
        }
        if let title, Double(timeMs) < Self.titleMs {
            let alpha = Self.fade(timeMs, total: Int(Self.titleMs))
            let origin = CGPoint(x: (outputSize.width - title.extent.width) / 2, y: (outputSize.height - title.extent.height) / 2)
            image = Self.place(title, alpha: alpha, at: origin).composited(over: image)
        }
        let remaining = timeline.durationMs - timeMs
        if let closing, Double(remaining) <= Self.titleMs {
            let alpha = Self.fade(Int(Self.titleMs) - remaining, total: Int(Self.titleMs) + Int(Self.fadeMs))
            let origin = CGPoint(x: (outputSize.width - closing.extent.width) / 2, y: outputSize.height * 0.3)
            image = Self.place(closing, alpha: alpha, at: origin).composited(over: image)
        }
        if let watermark {
            image = Self.place(watermark, alpha: 0.85, at: watermarkOrigin(for: watermark.extent.size)).composited(over: image)
        }
        return image.cropped(to: extent)
    }

    private func photoLayer(_ index: Int, progress: Double) throws(RenderError) -> CIImage {
        let entry = timeline.entries[index]
        let photo = try source(for: entry.photoIndex)
        let crop = entry.plan.crop(at: progress)
        let width = photo.extent.width, height = photo.extent.height
        // Normalized top-left crop → Core Image pixels (bottom-left origin).
        let pixels = CGRect(x: crop.minX * width, y: (1 - crop.maxY) * height, width: crop.width * width, height: crop.height * height)
        let transform = CGAffineTransform(translationX: -pixels.minX, y: -pixels.minY)
            .concatenating(CGAffineTransform(scaleX: outputSize.width / pixels.width, y: outputSize.height / pixels.height))
        return photo.clampedToExtent().transformed(by: transform).cropped(to: extent)
    }

    private func source(for photoIndex: Int) throws(RenderError) -> CIImage {
        if let cached = cache[photoIndex] { return cached }
        guard photoURLs.indices.contains(photoIndex) else { throw .unreadablePhoto }
        // Enough pixels for a 1.6× zoom on the longer output side; never the full original.
        let maxPixels = Int(max(outputSize.width, outputSize.height) * 1.6)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let imageSource = CGImageSourceCreateWithURL(photoURLs[photoIndex] as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
        else { throw .unreadablePhoto }
        let image = CIImage(cgImage: cgImage)
        if cache.count >= 2 { cache.removeAll() }
        cache[photoIndex] = image
        return image
    }

    static func blend(_ outgoing: CIImage, _ incoming: CIImage, mix: Double, kind: TemplateSpec.Transition.Kind, extent: CGRect) -> CIImage {
        func dissolve(_ a: CIImage, _ b: CIImage, _ t: Double) -> CIImage {
            a.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": b, "inputTime": t])
        }
        switch kind {
        case .cut:
            return mix < 0.5 ? outgoing : incoming
        case .crossfade:
            return dissolve(outgoing, incoming, mix)
        case .dipToBlack:
            let black = CIImage(color: .black).cropped(to: extent)
            return mix < 0.5 ? dissolve(outgoing, black, mix * 2) : dissolve(black, incoming, (mix - 0.5) * 2)
        case .slide:
            let offset = extent.width * CGFloat(mix)
            let left = outgoing.transformed(by: CGAffineTransform(translationX: -offset, y: 0))
            let right = incoming.transformed(by: CGAffineTransform(translationX: extent.width - offset, y: 0))
            return right.composited(over: left).cropped(to: extent)
        }
    }

    /// 0 → 1 over the first `fadeMs`, 1 → 0 over the last `fadeMs`.
    static func fade(_ elapsedMs: Int, total: Int) -> Double {
        let elapsed = Double(elapsedMs), remaining = Double(total - elapsedMs)
        return min(max(min(elapsed, remaining) / fadeMs, 0), 1)
    }

    static func place(_ overlay: CIImage, alpha: Double, at origin: CGPoint) -> CIImage {
        overlay
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(alpha))])
            .transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
    }

    private func watermarkOrigin(for size: CGSize) -> CGPoint {
        let margin = outputSize.width * 0.04
        switch watermarkPosition {
        case .bottomRight: return CGPoint(x: outputSize.width - size.width - margin, y: margin)
        case .bottomLeft: return CGPoint(x: margin, y: margin)
        case .topRight: return CGPoint(x: outputSize.width - size.width - margin, y: outputSize.height - size.height - margin)
        }
    }
}
