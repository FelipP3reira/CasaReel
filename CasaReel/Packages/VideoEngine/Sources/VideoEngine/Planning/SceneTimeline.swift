import CoreGraphics
import Domain
import Foundation

/// The full video as data: which photo shows when, how it moves, and how it hands over to the next one.
struct SceneTimeline: Equatable {
    struct Entry: Equatable {
        let photoIndex: Int
        let startMs: Int
        let durationMs: Int
        let plan: MotionPlanner.Plan
        /// Transition into the next entry; overlaps the end of this entry and the start of the next.
        let transition: TemplateSpec.Transition.Kind
        let transitionMs: Int
        let caption: String?

        var endMs: Int { startMs + durationMs }
    }

    let entries: [Entry]
    let durationMs: Int
    let fps: Int

    var frameCount: Int {
        Int((Double(durationMs) * Double(fps) / 1000).rounded(.up))
    }

    /// - Parameter photos: ordered photos with their pixel size, focus and faces (from the analysis).
    static func build(
        spec: TemplateSpec,
        aspect: VideoAspect,
        photos: [(size: CGSize, focus: CGRect, faces: [CGRect], caption: String?)],
        targetDurationMs: Int?
    ) -> SceneTimeline {
        guard !photos.isEmpty else { return SceneTimeline(entries: [], durationMs: 0, fps: spec.fps) }
        let outputAspect = CGFloat(aspect.renderSize.width) / CGFloat(aspect.renderSize.height)
        let scenes = photos.indices.map { spec.scenes[$0 % spec.scenes.count] }
        let factor = durationFactor(scenes: scenes, targetDurationMs: targetDurationMs)

        var entries: [Entry] = []
        var cursor = 0
        for (index, scene) in scenes.enumerated() {
            let duration = clampDuration(Int((Double(scene.durationMs) * factor).rounded()))
            let isLast = index == scenes.count - 1
            let transition = isLast ? nil : scene.transitionOut
            let kind = transition?.type ?? .cut
            let overlap = kind == .cut ? 0 : min(transition?.durationMs ?? 0, duration / 2)
            let photo = photos[index]
            let focus = scene.focus == .center ? CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5) : photo.focus
            entries.append(Entry(
                photoIndex: index, startMs: cursor, durationMs: duration,
                plan: MotionPlanner.plan(imageSize: photo.size, outputAspect: outputAspect, motion: scene.motion, focus: focus, faces: photo.faces),
                transition: kind, transitionMs: overlap,
                caption: scene.caption?.slot == .roomLabel ? photo.caption : nil
            ))
            cursor += duration - overlap
        }
        let total = min(entries.last?.endMs ?? 0, TemplateLimits.maxTotalDurationMs)
        return SceneTimeline(entries: entries.filter { $0.startMs < total }, durationMs: total, fps: spec.fps)
    }

    /// Scales scene durations toward the target, and always under the 180 s hard limit.
    static func durationFactor(scenes: [TemplateSpec.Scene], targetDurationMs: Int?) -> Double {
        let natural = Double(scenes.reduce(0) { $0 + $1.durationMs })
        guard natural > 0 else { return 1 }
        var factor = targetDurationMs.map { Double($0) / natural } ?? 1
        factor = min(factor, Double(TemplateLimits.maxTotalDurationMs) / natural)
        return max(factor, 0.01)
    }

    static func clampDuration(_ value: Int) -> Int {
        min(max(value, TemplateLimits.sceneDurationRange.lowerBound), TemplateLimits.sceneDurationRange.upperBound)
    }

    /// What is on screen at `timeMs`: one entry, or two while a transition runs.
    enum Frame: Equatable {
        case single(entry: Int, progress: Double)
        case transition(from: Int, to: Int, fromProgress: Double, toProgress: Double, mix: Double, kind: TemplateSpec.Transition.Kind)
    }

    func frame(at timeMs: Int) -> Frame? {
        guard let index = entries.lastIndex(where: { $0.startMs <= timeMs }) else { return nil }
        let entry = entries[index]
        func progress(_ e: Entry) -> Double { min(max(Double(timeMs - e.startMs) / Double(max(e.durationMs, 1)), 0), 1) }
        if index > 0 {
            let previous = entries[index - 1]
            if previous.transitionMs > 0, timeMs < previous.endMs {
                let mix = Double(timeMs - entry.startMs) / Double(previous.transitionMs)
                return .transition(from: index - 1, to: index, fromProgress: progress(previous), toProgress: progress(entry),
                                   mix: min(max(mix, 0), 1), kind: previous.transition)
            }
        }
        return .single(entry: index, progress: progress(entry))
    }
}
