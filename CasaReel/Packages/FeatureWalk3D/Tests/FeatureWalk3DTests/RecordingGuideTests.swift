import CoreGraphics
import Testing
import UIKit
@testable import FeatureWalk3D

struct RecordingGuideTests {
    private var allPages: [GuidePage] { GuideContent.video3D + GuideContent.photos }

    @Test func everySymbolExistsOnThisOS() {
        var names = Set(allPages.flatMap { $0.tips.map(\.symbol) })
        for page in allPages { if case .symbol(let name) = page.illustration { names.insert(name) } }
        names.formUnion(["checkmark.circle.fill", "xmark.circle.fill", "figure.walk", "play.rectangle.on.rectangle"])
        let missing = names.filter { UIImage(systemName: $0) == nil }.sorted()
        #expect(missing.isEmpty, "unknown SF Symbols: \(missing)")
    }

    @Test func video3DGuideCoversTheEssentialsAndShowsTheRoute() {
        let pages = GuideContent.video3D
        #expect(pages.count >= 5)
        #expect(pages.contains { $0.illustration == .route })
        #expect(pages.allSatisfy { !$0.tips.isEmpty })
        #expect(pages.flatMap(\.tips).contains { $0.kind == .avoid })
    }

    @Test func walkerFollowsTheRouteFromStartToEnd() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        #expect(Route.point(at: 0, in: rect) == CGPoint(x: 24, y: 50))
        #expect(Route.point(at: 1, in: rect) == CGPoint(x: 120, y: 82))
        // Halfway along the route is somewhere on the route, inside the plan.
        let middle = Route.point(at: 0.5, in: rect)
        #expect(rect.contains(middle))
        #expect(Route.point(at: -1, in: rect) == Route.point(at: 0, in: rect))
    }

    @Test func animationLoops() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(RouteIllustration.progress(at: start) == 0)
        #expect(abs(RouteIllustration.progress(at: start.addingTimeInterval(3)) - 0.5) < 1e-9)
        #expect(RouteIllustration.progress(at: start.addingTimeInterval(RouteIllustration.loopSeconds)) < 1e-9)
    }
}
