import Testing
@testable import FeaturePrivacy

struct FeaturePrivacyTests {
    @Test func exposesModuleName() {
        #expect(FeaturePrivacy.moduleName == "FeaturePrivacy")
    }
}
