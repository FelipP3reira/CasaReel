import CoreGraphics
import CryptoKit
import Domain
import Foundation
import Testing
@testable import VideoEngine

/// Builds a template JSON with overridable parts.
func templateJSON(
    slug: String = "test-template", aspect: String = #"["9:16","16:9"]"#, fps: Int = 30,
    scenes: [String]? = nil
) -> String {
    let defaultScene = #"{"source":"photo","duration_ms":3000,"focus":"saliency","motion":{"type":"kenburns","from":[0,0,1],"to":[0,0,1.2],"easing":"easeInOut"},"transition_out":{"type":"crossfade","duration_ms":500},"caption":{"slot":"room_label"}}"#
    let list = (scenes ?? [defaultScene]).joined(separator: ",")
    return #"{"slug":"\#(slug)","version":1,"aspect":\#(aspect),"fps":\#(fps),"scenes":[\#(list)],"audio":{"track_id":null,"duck_voiceover":false,"fade_out_ms":1000},"watermark":{"enabled":true,"position":"bottom_right"}}"#
}

func scene(duration: Int = 3000, motion: String = #"{"type":"kenburns","from":[0,0,1],"to":[0,0,1.2],"easing":"easeInOut"}"#, transition: String = #"{"type":"crossfade","duration_ms":500}"#) -> String {
    #"{"source":"photo","duration_ms":\#(duration),"focus":"saliency","motion":\#(motion),"transition_out":\#(transition),"caption":{"slot":"room_label"}}"#
}

struct TemplateSpecTests {
    @Test func bundledTemplatesLoadAndValidate() throws {
        let library = try TemplateLibrary()
        #expect(library.specs.map(\.slug.rawValue) == ["classic-clean", "cinematic-soft", "dynamic-social"])
        let socialSlug = try #require(TemplateSlug(rawValue: "dynamic-social"))
        let social = try #require(library.spec(for: socialSlug))
        #expect(social.aspect == [.vertical])
        #expect(library.specs.allSatisfy { $0.fps == 30 })
    }

    @Test func decodesValidSpec() throws {
        let spec = try TemplateSpec.decode(Data(templateJSON().utf8))
        #expect(spec.scenes.first?.transitionOut == .init(type: .crossfade, durationMs: 500))
        #expect(spec.scenes.first?.motion.easing == .easeInOut)
    }

    @Test(arguments: [
        (templateJSON(scenes: [scene(duration: 900)]), "scenes[0].duration_ms"),
        (templateJSON(scenes: [scene(duration: 8_500)]), "scenes[0].duration_ms"),
        (templateJSON(scenes: Array(repeating: scene(duration: 1_000), count: 61)), "scenes.count"),
        (templateJSON(scenes: []), "scenes.count"),
        (templateJSON(scenes: Array(repeating: scene(duration: 8_000), count: 23)), "duration"),
        (templateJSON(scenes: [scene(motion: #"{"type":"kenburns","from":[0,0],"to":[0,0,1],"easing":"linear"}"#)]), "scenes[0].motion"),
        (templateJSON(scenes: [scene(motion: #"{"type":"kenburns","from":[0,0,1],"to":[0,0,3],"easing":"linear"}"#)]), "scenes[0].motion"),
        (templateJSON(scenes: [scene(motion: #"{"type":"kenburns","from":[2,0,1],"to":[0,0,1],"easing":"linear"}"#)]), "scenes[0].motion"),
        (templateJSON(scenes: [scene(transition: #"{"type":"crossfade","duration_ms":1600}"#)]), "scenes[0].transition_out"),
        (templateJSON(fps: 240), "fps"),
        (templateJSON(aspect: "[]"), "aspect"),
    ])
    func rejectsSpecsOutsideLimits(json: String, field: String) {
        #expect(throws: TemplateError.invalid(field)) { try TemplateSpec.decode(Data(json.utf8)) }
    }

    @Test(arguments: [
        templateJSON(scenes: [scene(motion: #"{"type":"kenburns","from":[0,0,1],"to":[0,0,1],"easing":"bounce"}"#)]),
        templateJSON(scenes: [scene(transition: #"{"type":"explode","duration_ms":100}"#)]),
        templateJSON(slug: "../etc"),
        templateJSON(aspect: #"["4:3"]"#),
        "not json",
    ])
    func rejectsUnknownValuesAsMalformed(json: String) {
        #expect(throws: TemplateError.malformed) { try TemplateSpec.decode(Data(json.utf8)) }
    }
}

struct TemplateSignatureTests {
    private let key = Curve25519.Signing.PrivateKey()

    private func package(_ json: String, signedBy signer: Curve25519.Signing.PrivateKey? = nil, tamper: Bool = false) throws -> TemplatePackage {
        let payload = Data(json.utf8)
        let signature = try (signer ?? key).signature(for: payload)
        return TemplatePackage(payload: tamper ? Data(json.replacingOccurrences(of: "1.2", with: "1.9").utf8) : payload, signature: signature)
    }

    @Test func installsSignedTemplate() throws {
        var library = try TemplateLibrary(verificationKey: key.publicKey.rawRepresentation)
        let spec = try library.install(package(templateJSON(slug: "summer-sale")))
        #expect(spec.slug.rawValue == "summer-sale")
        #expect(library.specs.count == 4)
    }

    @Test func rejectsTamperedForeignOrUnverifiableTemplates() throws {
        var library = try TemplateLibrary(verificationKey: key.publicKey.rawRepresentation)
        #expect(throws: TemplateError.invalidSignature) { try library.install(package(templateJSON(), tamper: true)) }
        #expect(throws: TemplateError.invalidSignature) { try library.install(package(templateJSON(), signedBy: Curve25519.Signing.PrivateKey())) }

        var bundledOnly = try TemplateLibrary()
        #expect(throws: TemplateError.invalidSignature) { try bundledOnly.install(package(templateJSON())) }
        #expect(library.specs.count == 3)
    }

    @Test func signedButInvalidSpecIsStillRejected() throws {
        var library = try TemplateLibrary(verificationKey: key.publicKey.rawRepresentation)
        #expect(throws: TemplateError.invalid("fps")) { try library.install(package(templateJSON(fps: 500))) }
    }

    @Test func onlyNewerVersionsReplaceExistingTemplates() throws {
        var library = try TemplateLibrary(verificationKey: key.publicKey.rawRepresentation)
        let newer = templateJSON(slug: "classic-clean").replacingOccurrences(of: #""version":1"#, with: #""version":2"#)
        #expect(try library.install(package(newer)).version == 2)
        #expect(try library.install(package(templateJSON(slug: "classic-clean"))).version == 2)
        #expect(library.specs.count == 3)
    }
}

struct MotionPlannerTests {
    @Test func easingStartsAtZeroEndsAtOneAndIsMonotonic() {
        for easing in TemplateSpec.Easing.allCases {
            #expect(easing.apply(0) == 0)
            #expect(easing.apply(1) == 1)
            let samples = stride(from: 0.0, through: 1.0, by: 0.05).map(easing.apply)
            #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
        }
        #expect(TemplateSpec.Easing.easeInOut.apply(0.5) == 0.5)
        #expect(TemplateSpec.Easing.linear.apply(-1) == 0)
    }

    @Test func cropsNeverLeaveThePhotoAndKeepTheOutputAspect() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let size = CGSize(width: Double.random(in: 800...6000, using: &generator), height: Double.random(in: 800...6000, using: &generator))
            let aspect: CGFloat = Bool.random(using: &generator) ? 9.0 / 16.0 : 16.0 / 9.0
            let vector = { [Double.random(in: -1...1, using: &generator), Double.random(in: -1...1, using: &generator), Double.random(in: 1...2, using: &generator)] }
            let motion = TemplateSpec.Motion(type: .kenburns, from: vector(), to: vector(), easing: .easeInOut)
            let focusOrigin = CGPoint(x: Double.random(in: 0...0.9, using: &generator), y: Double.random(in: 0...0.9, using: &generator))
            let focus = CGRect(origin: focusOrigin, size: CGSize(width: 0.1, height: 0.1))

            let plan = MotionPlanner.plan(imageSize: size, outputAspect: aspect, motion: motion, focus: focus, faces: [])

            for progress in [0, 0.25, 0.5, 0.75, 1.0] {
                let crop = plan.crop(at: progress)
                #expect(crop.minX >= -1e-9 && crop.minY >= -1e-9 && crop.maxX <= 1 + 1e-9 && crop.maxY <= 1 + 1e-9)
                let pixelAspect = (crop.width * size.width) / (crop.height * size.height)
                #expect(abs(pixelAspect - aspect) / aspect < 0.01)
            }
        }
    }

    @Test func zoomedCropMovesToIncludeAFaceItWouldCut() {
        // 4:3 photo, 16:9 output, 1.6× zoom pushed right: the crop spans x 0.175–0.8, cutting this face in half.
        let face = CGRect(x: 0.12, y: 0.3, width: 0.12, height: 0.15)
        let motion = TemplateSpec.Motion(type: .kenburns, from: [1, 0, 1.6], to: [1, 0, 1.6], easing: .linear)
        let plan = MotionPlanner.plan(imageSize: CGSize(width: 4000, height: 3000), outputAspect: 16 / 9,
                                      motion: motion, focus: CGRect(x: 0.2, y: 0.3, width: 0.2, height: 0.2), faces: [face])
        #expect(plan.from.contains(face))
        let unconstrained = MotionPlanner.plan(imageSize: CGSize(width: 4000, height: 3000), outputAspect: 16 / 9,
                                               motion: motion, focus: CGRect(x: 0.2, y: 0.3, width: 0.2, height: 0.2), faces: [])
        #expect(unconstrained.from.intersects(face) && !unconstrained.from.contains(face), "precondition: without faces the crop cuts it")
    }

    @Test func staticMotionDoesNotMove() {
        let motion = TemplateSpec.Motion(type: .static, from: [0, 0, 1.1], to: [1, 1, 2], easing: .linear)
        let plan = MotionPlanner.plan(imageSize: CGSize(width: 4000, height: 3000), outputAspect: 9 / 16,
                                      motion: motion, focus: CGRect(x: 0, y: 0, width: 1, height: 1), faces: [])
        #expect(plan.from == plan.to)
    }
}

struct SceneTimelineTests {
    private let photo = (size: CGSize(width: 4000, height: 3000), focus: CGRect(x: 0, y: 0, width: 1, height: 1), faces: [CGRect](), caption: Optional("Sala"))

    private func spec(_ json: String = templateJSON()) throws -> TemplateSpec {
        try TemplateSpec.decode(Data(json.utf8))
    }

    @Test func durationIsSumOfScenesMinusOverlaps() throws {
        let timeline = SceneTimeline.build(spec: try spec(), aspect: .vertical, photos: Array(repeating: photo, count: 4), targetDurationMs: nil)
        #expect(timeline.entries.count == 4)
        #expect(timeline.durationMs == 4 * 3000 - 3 * 500)
        #expect(timeline.entries.last?.transitionMs == 0, "the last scene has no outgoing transition")
        #expect(timeline.frameCount == Int((Double(timeline.durationMs) * 30 / 1000).rounded(.up)))
        #expect(timeline.entries.allSatisfy { $0.caption == "Sala" })
    }

    @Test func scalesTowardTargetDurationWithinSceneLimits() throws {
        let photos = Array(repeating: photo, count: 5)
        let short = SceneTimeline.build(spec: try spec(), aspect: .horizontal, photos: photos, targetDurationMs: 2_000)
        #expect(short.entries.allSatisfy { $0.durationMs == TemplateLimits.sceneDurationRange.lowerBound })
        let long = SceneTimeline.build(spec: try spec(), aspect: .horizontal, photos: photos, targetDurationMs: 30_000)
        #expect(long.entries.allSatisfy { $0.durationMs == 6_000 })
    }

    @Test func neverExceedsHardLimit() throws {
        let slow = try spec(templateJSON(scenes: [scene(duration: 8_000)]))
        let timeline = SceneTimeline.build(spec: slow, aspect: .vertical, photos: Array(repeating: photo, count: 40), targetDurationMs: 600_000)
        #expect(timeline.durationMs <= TemplateLimits.maxTotalDurationMs)
    }

    @Test func framesReportTransitionsAtTheRightTime() throws {
        let timeline = SceneTimeline.build(spec: try spec(), aspect: .vertical, photos: [photo, photo], targetDurationMs: nil)
        #expect(timeline.frame(at: 1_000) == .single(entry: 0, progress: 1_000.0 / 3_000))
        guard case .transition(let from, let to, _, _, let mix, let kind) = timeline.frame(at: 2_750) else {
            Issue.record("expected a transition")
            return
        }
        #expect((from, to, kind) == (0, 1, .crossfade))
        #expect(abs(mix - 0.5) < 1e-9)
        #expect(timeline.frame(at: 4_000) == .single(entry: 1, progress: 1_500.0 / 3_000))
        #expect(SceneTimeline.build(spec: try spec(), aspect: .vertical, photos: [], targetDurationMs: nil).frame(at: 0) == nil)
    }
}
