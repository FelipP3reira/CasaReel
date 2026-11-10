import CoreGraphics
import Foundation

extension TemplateSpec.Easing {
    /// Deterministic curves; the server-side worker must use the exact same formulas.
    /// - linear: t · easeIn: t² · easeOut: 1 − (1 − t)² · easeInOut: 3t² − 2t³ (smoothstep)
    func apply(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        switch self {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return 1 - (1 - t) * (1 - t)
        case .easeInOut: return t * t * (3 - 2 * t)
        }
    }
}

/// Plans the Ken Burns crop for one photo. All rects are normalized to the photo (0–1, top-left origin).
struct MotionPlanner {
    struct Plan: Equatable {
        let from: CGRect
        let to: CGRect
        let easing: TemplateSpec.Easing
        /// Extra zoom of the nearest depth layer at the end of the scene; 0 means a flat photo.
        var parallax: Double = 0

        func crop(at progress: Double) -> CGRect {
            let t = easing.apply(progress)
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * CGFloat(t) }
            return CGRect(x: mix(from.minX, to.minX), y: mix(from.minY, to.minY),
                          width: mix(from.width, to.width), height: mix(from.height, to.height))
        }
    }

    /// - Parameters:
    ///   - imageSize: photo size in pixels (after orientation).
    ///   - outputAspect: output width / height.
    ///   - focus: region of interest; the crop is centered on it.
    ///   - faces: regions that must never be cut by the crop edge.
    static func plan(
        imageSize: CGSize, outputAspect: CGFloat, motion: TemplateSpec.Motion,
        focus: CGRect, faces: [CGRect]
    ) -> Plan {
        let imageAspect = imageSize.width / max(imageSize.height, 1)
        // Largest crop with the output aspect that fits inside the photo ("aspect fill").
        let base = imageAspect > outputAspect
            ? CGSize(width: outputAspect / imageAspect, height: 1)
            : CGSize(width: 1, height: imageAspect / outputAspect)
        let isStatic = motion.type == .static
        let from = crop(base: base, vector: motion.from, focus: focus, faces: faces)
        let to = isStatic ? from : crop(base: base, vector: motion.to, focus: focus, faces: faces)
        let parallax = motion.type == .walk ? motion.parallax ?? TemplateSpec.Motion.defaultParallax : 0
        return Plan(from: from, to: to, easing: motion.easing, parallax: parallax)
    }

    static func crop(base: CGSize, vector: [Double], focus: CGRect, faces: [CGRect]) -> CGRect {
        let scale = CGFloat(min(max(vector.count > 2 ? vector[2] : 1, 1), 2))
        let size = CGSize(width: base.width / scale, height: base.height / scale)
        // Center on the focus, then move by the template offset into the free space on each side.
        let center = CGPoint(x: focus.midX, y: focus.midY)
        let slack = CGSize(width: (1 - size.width) / 2, height: (1 - size.height) / 2)
        var rect = CGRect(
            x: center.x - size.width / 2 + CGFloat(vector.first ?? 0) * slack.width,
            y: center.y - size.height / 2 + CGFloat(vector.count > 1 ? vector[1] : 0) * slack.height,
            width: size.width, height: size.height
        )
        rect = clamp(rect)
        for face in faces where rect.intersects(face) && !rect.contains(face) {
            rect = clamp(include(face, in: rect))
        }
        return rect
    }

    /// Shifts `rect` (same size) so it fully contains `face` when it fits.
    static func include(_ face: CGRect, in rect: CGRect) -> CGRect {
        var shifted = rect
        if face.width <= rect.width {
            if face.minX < rect.minX { shifted.origin.x = face.minX }
            if face.maxX > rect.maxX { shifted.origin.x = face.maxX - rect.width }
        }
        if face.height <= rect.height {
            if face.minY < rect.minY { shifted.origin.y = face.minY }
            if face.maxY > rect.maxY { shifted.origin.y = face.maxY - rect.height }
        }
        return shifted
    }

    /// Keeps the crop inside the photo.
    static func clamp(_ rect: CGRect) -> CGRect {
        let width = min(rect.width, 1), height = min(rect.height, 1)
        return CGRect(
            x: min(max(rect.minX, 0), 1 - width), y: min(max(rect.minY, 0), 1 - height),
            width: width, height: height
        )
    }
}
