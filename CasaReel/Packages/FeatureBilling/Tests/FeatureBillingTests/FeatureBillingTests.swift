import Testing
@testable import FeatureBilling

struct FeatureBillingTests {
    @Test func exposesModuleName() {
        #expect(FeatureBilling.moduleName == "FeatureBilling")
    }
}
