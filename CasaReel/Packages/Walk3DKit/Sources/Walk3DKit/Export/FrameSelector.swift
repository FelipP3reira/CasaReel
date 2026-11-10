import Foundation

/// Chooses which video frames go into the 3D reconstruction.
///
/// Structure-from-motion needs plenty of overlap between neighboring frames, so frames are kept densely;
/// what hurts it is motion blur and many copies of the same view (the camera standing still).
/// Candidates are grouped into fixed time windows; the sharpest of each window is kept unless it is a
/// near-duplicate of the previous pick or much blurrier than the video's typical frame.
struct FrameSelector {
    struct Candidate: Equatable {
        let time: Double
        let sharpness: Double
        let hash: UInt64
    }

    /// Seconds per kept frame (at most one frame per window).
    let window: Double
    /// Picks closer than this (in dHash bits) to the previous pick are dropped as "standing still".
    var minHashDistance = 3
    /// A pick below this fraction of the running median sharpness is dropped as blurred.
    var minRelativeSharpness = 0.35

    private(set) var picks: [Candidate] = []
    private var currentWindow: Int?
    private var best: Candidate?
    private var sharpnessHistory: [Double] = []

    init(window: Double) {
        self.window = max(window, 0.05)
    }

    /// Feeds candidates in time order. Returns the candidate picked when a window closes, if any.
    mutating func add(_ candidate: Candidate) -> Candidate? {
        let index = Int(candidate.time / window)
        var closed: Candidate?
        if let currentWindow, index != currentWindow {
            closed = closeWindow()
        }
        currentWindow = index
        if candidate.sharpness > (best?.sharpness ?? -1) { best = candidate }
        return closed
    }

    /// Closes the last window; call once after the final candidate.
    mutating func finish() -> Candidate? {
        closeWindow()
    }

    private mutating func closeWindow() -> Candidate? {
        defer { best = nil }
        guard let best else { return nil }
        sharpnessHistory.append(best.sharpness)
        let median = sharpnessHistory.sorted()[sharpnessHistory.count / 2]
        if best.sharpness < median * minRelativeSharpness { return nil }
        if let last = picks.last, ImageMetrics.distance(last.hash, best.hash) < minHashDistance { return nil }
        picks.append(best)
        return best
    }

    /// Window length so all videos together stay within `maxFrames`, never denser than `minWindow`.
    static func window(totalDuration: Double, maxFrames: Int, minWindow: Double = 0.5) -> Double {
        guard maxFrames > 0, totalDuration > 0 else { return minWindow }
        return max(minWindow, totalDuration / Double(maxFrames))
    }
}
