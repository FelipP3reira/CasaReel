import Domain
import Foundation

/// The versioned template JSON (docs/04, section 3), shared with the server-side worker.
/// Pure data: nothing in a spec is ever executed; unknown enum values make decoding fail.
public struct TemplateSpec: Codable, Sendable, Equatable {
    public enum Easing: String, Codable, Sendable, CaseIterable {
        case linear, easeIn, easeOut, easeInOut
    }

    public struct Motion: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable {
            case kenburns
            case `static`
            /// Ken Burns crop plus depth parallax: nearer parts of the photo grow faster, like walking in.
            case walk
        }

        public let type: Kind
        /// `[x, y, scale]`: x/y in −1…1 move the crop within the free space around the focus, scale ≥ 1 zooms in.
        public let from: [Double]
        public let to: [Double]
        public let easing: Easing
        /// `walk` only: extra zoom of the nearest layer at the end of the scene (0.2 = 20 %). Defaults to `defaultParallax`.
        public var parallax: Double? = nil

        public static let defaultParallax = 0.2
    }

    public struct Transition: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable {
            case cut
            case crossfade
            case dipToBlack = "dip_to_black"
            case slide
            /// Keeps pushing into the outgoing photo while the next one arrives already moving.
            case walkThrough = "walk_through"
        }

        public let type: Kind
        public let durationMs: Int
    }

    public struct Caption: Codable, Sendable, Equatable {
        public enum Slot: String, Codable, Sendable {
            case roomLabel = "room_label"
            case title
            case none
        }

        public let slot: Slot
    }

    public struct Scene: Codable, Sendable, Equatable {
        public enum Source: String, Codable, Sendable {
            case photo
        }

        public enum Focus: String, Codable, Sendable {
            case saliency
            case center
        }

        public let source: Source
        public let durationMs: Int
        public let motion: Motion
        public let focus: Focus
        public let transitionOut: Transition?
        public let caption: Caption?
    }

    public struct Audio: Codable, Sendable, Equatable {
        public let trackId: String?
        public let duckVoiceover: Bool
        public let fadeOutMs: Int
    }

    public struct Watermark: Codable, Sendable, Equatable {
        public enum Position: String, Codable, Sendable {
            case bottomRight = "bottom_right"
            case bottomLeft = "bottom_left"
            case topRight = "top_right"
        }

        public let enabled: Bool
        public let position: Position
    }

    public let slug: TemplateSlug
    public let version: Int
    public let aspect: [VideoAspect]
    public let fps: Int
    /// A pattern applied to the photos in order and repeated when there are more photos than scenes.
    public let scenes: [Scene]
    public let audio: Audio?
    public let watermark: Watermark?
}

public enum TemplateError: Error, Sendable, Equatable {
    case malformed
    case invalid(String)
    case invalidSignature
}

/// Hard limits that protect the device from oversized or hostile specs.
public enum TemplateLimits {
    public static let maxTotalDurationMs = 180_000
    public static let sceneDurationRange = 1_000...8_000
    public static let maxScenes = 60
    public static let fpsRange = 24...60
    public static let scaleRange = 1.0...2.0
    public static let offsetRange = -1.0...1.0
    /// Beyond ~30 % the stretched edges between depth layers become visible.
    public static let parallaxRange = 0.0...0.3
    public static let maxTransitionMs = 2_000
    public static let maxFadeOutMs = 5_000
}

extension TemplateSpec {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Decodes and validates; any failure is a `TemplateError`.
    public static func decode(_ data: Data) throws(TemplateError) -> TemplateSpec {
        let spec: TemplateSpec
        do {
            spec = try decoder.decode(TemplateSpec.self, from: data)
        } catch {
            throw .malformed
        }
        try spec.validate()
        return spec
    }

    public func validate() throws(TemplateError) {
        guard version >= 1 else { throw .invalid("version") }
        guard !aspect.isEmpty else { throw .invalid("aspect") }
        guard TemplateLimits.fpsRange.contains(fps) else { throw .invalid("fps") }
        guard (1...TemplateLimits.maxScenes).contains(scenes.count) else { throw .invalid("scenes.count") }
        guard scenes.reduce(0, { $0 + $1.durationMs }) <= TemplateLimits.maxTotalDurationMs else { throw .invalid("duration") }
        for (index, scene) in scenes.enumerated() {
            guard TemplateLimits.sceneDurationRange.contains(scene.durationMs) else { throw .invalid("scenes[\(index)].duration_ms") }
            for vector in [scene.motion.from, scene.motion.to] {
                guard vector.count == 3, vector.allSatisfy(\.isFinite),
                      TemplateLimits.offsetRange.contains(vector[0]), TemplateLimits.offsetRange.contains(vector[1]),
                      TemplateLimits.scaleRange.contains(vector[2])
                else { throw .invalid("scenes[\(index)].motion") }
            }
            if let parallax = scene.motion.parallax {
                guard parallax.isFinite, TemplateLimits.parallaxRange.contains(parallax) else { throw .invalid("scenes[\(index)].motion") }
            }
            if let transition = scene.transitionOut {
                let limit = min(TemplateLimits.maxTransitionMs, scene.durationMs / 2)
                guard (0...limit).contains(transition.durationMs) else { throw .invalid("scenes[\(index)].transition_out") }
            }
        }
        if let audio, !(0...TemplateLimits.maxFadeOutMs).contains(audio.fadeOutMs) { throw .invalid("audio.fade_out_ms") }
    }

    public var info: VideoTemplateInfo {
        VideoTemplateInfo(slug: slug, version: version, aspects: aspect, sceneCount: scenes.count)
    }
}
