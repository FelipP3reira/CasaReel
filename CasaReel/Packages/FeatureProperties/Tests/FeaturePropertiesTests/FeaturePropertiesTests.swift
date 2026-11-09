import Testing
@testable import FeatureProperties

struct FeaturePropertiesTests {
    @Test func exposesModuleName() {
        #expect(FeatureProperties.moduleName == "FeatureProperties")
    }
}
