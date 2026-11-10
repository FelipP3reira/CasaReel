import CoreGraphics

/// Estimates relative depth from a single photo (implemented by `MediaKit` with an on-device Core ML model).
/// Used by the "walk" motion to move near and far parts of a photo at different speeds.
public protocol DepthEstimating: Sendable {
    /// An 8-bit grayscale map, normalized so white is the nearest point and black the farthest.
    /// Its size may differ from the photo's; callers stretch it over the photo. `nil` when estimation fails.
    func depthMap(for image: CGImage) -> CGImage?
}
