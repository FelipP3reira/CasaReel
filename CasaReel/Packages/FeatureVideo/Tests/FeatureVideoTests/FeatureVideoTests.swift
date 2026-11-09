import Testing
@testable import FeatureVideo

struct FeatureVideoTests {
    @Test func exposesModuleName() {
        #expect(FeatureVideo.moduleName == "FeatureVideo")
    }
}
