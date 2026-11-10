import CoreGraphics
import Testing
@testable import MediaKit

struct DepthEstimationTests {
    @Test func normalizeStretchesToFullRange() {
        #expect(CoreMLDepthEstimator.normalize([0, 5, 10]) == [0, 128, 255])
        #expect(CoreMLDepthEstimator.normalize([-2, 2]) == [0, 255])
    }

    @Test func flatOrBrokenMapsCarryNoDepthCue() {
        #expect(CoreMLDepthEstimator.normalize([3, 3, 3]) == [128, 128, 128])
        #expect(CoreMLDepthEstimator.normalize([.nan, 1, 2]) == [0, 0, 255])
        #expect(CoreMLDepthEstimator.normalize([.nan, .infinity]) == [0, 0])
        #expect(CoreMLDepthEstimator.normalize([]).isEmpty)
    }

    @Test func bundledModelProducesAGrayscaleMap() throws {
        let photo = try #require(Fixtures.image(width: 800, height: 600))
        let map = try #require(CoreMLDepthEstimator().depthMap(for: photo))
        #expect(map.width == 518 && map.height == 392)
        #expect(map.bitsPerPixel == 8)
    }
}
