import Foundation
import Testing
@testable import Domain

struct AppConfigurationTests {
    private let valid: [String: Any] = [
        "CREnvironment": "staging",
        "CRAPIBaseURL": "https://api.staging.casareel.example/v1",
        "CRUniversalLinkHost": "staging.casareel.example",
    ]

    private func replacing(_ key: String, with value: Any?) -> [String: Any] {
        var dictionary = valid
        dictionary[key] = value
        return dictionary
    }

    @Test func parsesValidConfiguration() throws {
        let configuration = try AppConfiguration(infoDictionary: valid)
        #expect(configuration.environment == .staging)
        #expect(configuration.apiBaseURL.absoluteString == "https://api.staging.casareel.example/v1")
        #expect(configuration.universalLinkHost == "staging.casareel.example")
    }

    @Test func rejectsNonHTTPSURL() {
        #expect(throws: AppConfigurationError.invalidValue("CRAPIBaseURL")) {
            try AppConfiguration(infoDictionary: replacing("CRAPIBaseURL", with: "http://api.casareel.example/v1"))
        }
    }

    @Test func rejectsMissingEnvironment() {
        #expect(throws: AppConfigurationError.missingValue("CREnvironment")) {
            try AppConfiguration(infoDictionary: replacing("CREnvironment", with: nil))
        }
    }

    @Test func rejectsUnknownEnvironment() {
        #expect(throws: AppConfigurationError.invalidValue("CREnvironment")) {
            try AppConfiguration(infoDictionary: replacing("CREnvironment", with: "production"))
        }
    }

    @Test func rejectsMissingUniversalLinkHost() {
        #expect(throws: AppConfigurationError.missingValue("CRUniversalLinkHost")) {
            try AppConfiguration(infoDictionary: replacing("CRUniversalLinkHost", with: nil))
        }
    }

    @Test(arguments: ["", "https://casareel.example", "casareel", "casareel.example/app", "evil.com@casareel.example"])
    func rejectsInvalidUniversalLinkHost(_ host: String) {
        #expect(throws: AppConfigurationError.invalidValue("CRUniversalLinkHost")) {
            try AppConfiguration(infoDictionary: replacing("CRUniversalLinkHost", with: host))
        }
    }
}
