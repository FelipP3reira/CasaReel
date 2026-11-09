import Testing
@testable import FeatureAuth

struct FeatureAuthTests {
    @Test func exposesModuleName() {
        #expect(FeatureAuth.moduleName == "FeatureAuth")
    }
}
