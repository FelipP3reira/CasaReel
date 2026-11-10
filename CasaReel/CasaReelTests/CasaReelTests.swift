import Foundation
import Testing

/// App-target checks for the Walk 3D privacy configuration.
struct Walk3DConfigurationTests {
    @Test func cameraUsageDescriptionIsPresent() {
        let description = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String

        #expect(description?.isEmpty == false)
    }

    @Test func cameraUsageDescriptionExplainsOnDeviceProcessing() {
        let description = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String ?? ""

        #expect(description.localizedCaseInsensitiveContains("Walk 3D"))
        #expect(description.localizedCaseInsensitiveContains("iPhone"))
    }
}
