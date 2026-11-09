import Testing
@testable import FeaturePhotos

struct FeaturePhotosTests {
    @Test func exposesModuleName() {
        #expect(FeaturePhotos.moduleName == "FeaturePhotos")
    }
}
