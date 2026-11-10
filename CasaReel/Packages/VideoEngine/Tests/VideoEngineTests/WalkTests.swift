import CoreGraphics
import CoreImage
import Domain
import Foundation
import Testing
@testable import VideoEngine

struct WalkTemplateTests {
    private let walk = #"{"type":"walk","from":[0,0,1],"to":[0,0,1.2],"easing":"linear","parallax":0.25}"#

    @Test func walkSpecDecodesAndCarriesParallaxIntoThePlan() throws {
        let spec = try TemplateSpec.decode(Data(templateJSON(scenes: [scene(motion: walk, transition: #"{"type":"walk_through","duration_ms":800}"#)]).utf8))
        #expect(spec.scenes[0].motion.type == .walk)
        #expect(spec.scenes[0].transitionOut?.type == .walkThrough)
        let plan = MotionPlanner.plan(imageSize: CGSize(width: 4000, height: 3000), outputAspect: 9 / 16,
                                      motion: spec.scenes[0].motion, focus: CGRect(x: 0, y: 0, width: 1, height: 1), faces: [])
        #expect(plan.parallax == 0.25)
    }

    @Test func parallaxDefaultsForWalkAndIsZeroOtherwise() {
        let size = CGSize(width: 4000, height: 3000), focus = CGRect(x: 0, y: 0, width: 1, height: 1)
        let walk = TemplateSpec.Motion(type: .walk, from: [0, 0, 1], to: [0, 0, 1.2], easing: .linear)
        let kenBurns = TemplateSpec.Motion(type: .kenburns, from: [0, 0, 1], to: [0, 0, 1.2], easing: .linear, parallax: 0.3)
        #expect(MotionPlanner.plan(imageSize: size, outputAspect: 1, motion: walk, focus: focus, faces: []).parallax == TemplateSpec.Motion.defaultParallax)
        #expect(MotionPlanner.plan(imageSize: size, outputAspect: 1, motion: kenBurns, focus: focus, faces: []).parallax == 0)
    }

    @Test(arguments: [-0.1, 0.31, 5])
    func rejectsParallaxOutsideLimits(parallax: Double) {
        let motion = #"{"type":"walk","from":[0,0,1],"to":[0,0,1.2],"easing":"linear","parallax":\#(parallax)}"#
        #expect(throws: TemplateError.invalid("scenes[0].motion")) { try TemplateSpec.decode(Data(templateJSON(scenes: [scene(motion: motion)]).utf8)) }
    }

    @Test func bundledWalkTemplateUsesWalkEverywhere() throws {
        let slug = try #require(TemplateSlug(rawValue: "walk-tour"))
        let spec = try #require(try TemplateLibrary().spec(for: slug))
        #expect(spec.scenes.allSatisfy { $0.motion.type == .walk && $0.transitionOut?.type == .walkThrough })
    }
}

struct WalkCompositorTests {
    private let context = CIContext()
    private let extent = CGRect(x: 0, y: 0, width: 400, height: 400)
    /// A green "sofa" right of center; everything else is black and far away.
    private let sofa = CGRect(x: 250, y: 180, width: 50, height: 40)

    private var photo: CIImage {
        CIImage(color: .green).cropped(to: sofa).composited(over: CIImage(color: .black).cropped(to: extent)).clampedToExtent()
    }

    private var depth: CIImage {
        CIImage(color: .white).cropped(to: sofa).composited(over: CIImage(color: .black).cropped(to: extent)).clampedToExtent()
    }

    private func green(_ image: CIImage, at point: CGPoint) -> Bool {
        let (red, green, blue) = RenderFixtures.pixel(of: image, at: point, context: context)
        return green > 0.8 && red < 0.2 && blue < 0.2
    }

    @Test func startsAsTheFlatPhoto() {
        let frame = WalkCompositor.compose(photo: photo, depth: depth, progress: 0, parallax: 0.3, extent: extent)
        #expect(frame.extent == extent)
        #expect(green(frame, at: CGPoint(x: 290, y: 200)))
        #expect(!green(frame, at: CGPoint(x: 315, y: 200)))
    }

    @Test func nearObjectsGrowFasterThanTheRoom() {
        // Nearest band: 1 + 0.3 × 0.875 ≈ 1.26× about the center, so the sofa's right edge (x 300) reaches ~326.
        // The farthest band only zooms ~1.04×, which would put that edge at ~304.
        let frame = WalkCompositor.compose(photo: photo, depth: depth, progress: 1, parallax: 0.3, extent: extent)
        #expect(green(frame, at: CGPoint(x: 315, y: 200)))
        let flatDepth = CIImage(color: .black).cropped(to: extent).clampedToExtent()
        let farOnly = WalkCompositor.compose(photo: photo, depth: flatDepth, progress: 1, parallax: 0.3, extent: extent)
        #expect(!green(farOnly, at: CGPoint(x: 315, y: 200)))
    }

    @Test func fallbackDepthIsFarAtTheVanishingPointAndNearAtTheFloor() {
        let depth = WalkCompositor.fallbackDepth(over: extent, vanishingPoint: CGPoint(x: 0.5, y: 0.4))
        let far = RenderFixtures.pixel(of: depth, at: CGPoint(x: 200, y: 240), context: context).0
        let floor = RenderFixtures.pixel(of: depth, at: CGPoint(x: 200, y: 2), context: context).0
        let corner = RenderFixtures.pixel(of: depth, at: CGPoint(x: 2, y: 398), context: context).0
        #expect(far < 0.1)
        #expect(floor > 0.9)
        #expect(corner > far)
    }

    @Test func walkThroughGoesFromOutgoingToIncoming() {
        let red = CIImage(color: .red).cropped(to: extent), blue = CIImage(color: .blue).cropped(to: extent)
        let probe = CGPoint(x: 100, y: 100)
        let start = RenderFixtures.pixel(of: WalkCompositor.walkThrough(red, blue, mix: 0, extent: extent), at: probe, context: context)
        let end = RenderFixtures.pixel(of: WalkCompositor.walkThrough(red, blue, mix: 1, extent: extent), at: probe, context: context)
        #expect(start.0 > 0.9 && start.2 < 0.1)
        #expect(end.2 > 0.9 && end.0 < 0.1)
    }

    @Test func rendererUsesTheEstimatorForWalkScenes() throws {
        let fixtures = try RenderFixtures()
        let spec = try TemplateSpec.decode(Data(templateJSON(scenes: [scene(motion: #"{"type":"walk","from":[0,0,1],"to":[0,0,1.2],"easing":"linear"}"#)]).utf8))
        let red = try fixtures.photo(red: 1, green: 0, blue: 0)
        let photos = [(size: CGSize(width: red.width, height: red.height), focus: CGRect(x: 0, y: 0, width: 1, height: 1), faces: [CGRect](), caption: String?.none)]
        let timeline = SceneTimeline.build(spec: spec, aspect: .horizontal, photos: photos, targetDurationMs: nil)
        let estimator = CountingEstimator()
        let renderer = FrameRenderer(timeline: timeline, photoURLs: [red.fileURL], outputSize: CGSize(width: 640, height: 360),
                                     context: context, title: nil, watermark: false, watermarkPosition: .bottomRight, depthEstimator: estimator)
        for time in [0, 1000, 2000] { _ = try renderer.image(atMs: time) }
        #expect(estimator.calls == 1, "depth is estimated once per photo")
    }
}

/// Returns a flat map and counts calls.
private final class CountingEstimator: DepthEstimating, @unchecked Sendable {
    private(set) var calls = 0

    func depthMap(for image: CGImage) -> CGImage? {
        calls += 1
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        return context?.makeImage()
    }
}
