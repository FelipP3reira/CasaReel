import Foundation
import Testing
@testable import Domain

struct AppConfigurationTests {
    @Test func parsesValidConfiguration() throws {
        let configuration = try AppConfiguration(infoDictionary: [
            "CREnvironment": "staging",
            "CRAPIBaseURL": "https://api.staging.casareel.example/v1",
        ])
        #expect(configuration.environment == .staging)
        #expect(configuration.apiBaseURL.absoluteString == "https://api.staging.casareel.example/v1")
    }

    @Test func rejectsNonHTTPSURL() {
        #expect(throws: AppConfigurationError.invalidValue("CRAPIBaseURL")) {
            try AppConfiguration(infoDictionary: [
                "CREnvironment": "debug",
                "CRAPIBaseURL": "http://api.casareel.example/v1",
            ])
        }
    }

    @Test func rejectsMissingEnvironment() {
        #expect(throws: AppConfigurationError.missingValue("CREnvironment")) {
            try AppConfiguration(infoDictionary: ["CRAPIBaseURL": "https://api.casareel.example/v1"])
        }
    }

    @Test func rejectsUnknownEnvironment() {
        #expect(throws: AppConfigurationError.invalidValue("CREnvironment")) {
            try AppConfiguration(infoDictionary: [
                "CREnvironment": "production",
                "CRAPIBaseURL": "https://api.casareel.example/v1",
            ])
        }
    }
}
