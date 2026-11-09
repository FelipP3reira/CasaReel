import Foundation
import Testing
@testable import Domain

private let pinA = Data(repeating: 1, count: 32).base64EncodedString()
private let pinB = Data(repeating: 2, count: 32).base64EncodedString()

struct AppConfigurationTests {
    private let valid: [String: Any] = [
        "CREnvironment": "staging",
        "CRAPIBaseURL": "https://api.staging.casareel.example/v1",
        "CRUniversalLinkHost": "staging.casareel.example",
        "CRPublicKeyPins": "\(pinA), \(pinB)",
        "CRConfigSigningPublicKey": Data(repeating: 7, count: 32).base64EncodedString(),
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
        #expect(configuration.publicKeyPins == [pinA, pinB])
        #expect(configuration.configSigningPublicKey == Data(repeating: 7, count: 32))
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

    @Test(arguments: [
        "",
        "\(pinA)",
        "\(pinA),\(pinA)",
        "\(pinA),not-base64",
        "\(pinA),\(Data(repeating: 3, count: 20).base64EncodedString())",
    ])
    func rejectsInvalidPins(_ pins: String) {
        #expect(throws: AppConfigurationError.invalidValue("CRPublicKeyPins")) {
            try AppConfiguration(infoDictionary: replacing("CRPublicKeyPins", with: pins))
        }
    }

    @Test func rejectsMissingPins() {
        #expect(throws: AppConfigurationError.missingValue("CRPublicKeyPins")) {
            try AppConfiguration(infoDictionary: replacing("CRPublicKeyPins", with: nil))
        }
    }

    @Test(arguments: [nil, "", Data(repeating: 1, count: 31).base64EncodedString()])
    func rejectsInvalidSigningKey(_ key: String?) {
        let expected: AppConfigurationError = key == nil
            ? .missingValue("CRConfigSigningPublicKey")
            : .invalidValue("CRConfigSigningPublicKey")
        #expect(throws: expected) {
            try AppConfiguration(infoDictionary: replacing("CRConfigSigningPublicKey", with: key))
        }
    }
}
