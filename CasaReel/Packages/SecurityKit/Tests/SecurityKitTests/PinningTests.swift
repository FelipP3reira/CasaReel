import CryptoKit
import Domain
import Foundation
import Testing
@testable import SecurityKit

struct PinningTests {
    private let backupPin = Data(repeating: 9, count: 32).base64EncodedString()

    private func validator(pins: [String]) -> PinValidator {
        PinValidator(policy: PinningPolicy(pinnedHosts: [TestCertificates.host], pins: pins))
    }

    @Test func pinMatchesOpenSSLComputation() {
        #expect(SPKIHasher.pin(for: TestCertificates.good) == TestCertificates.goodPin)
        #expect(SPKIHasher.pin(for: TestCertificates.other) == TestCertificates.otherPin)
    }

    @Test func acceptsCertificateWithPinnedKey() {
        let trust = TestCertificates.trust(for: TestCertificates.good)
        #expect(validator(pins: [TestCertificates.goodPin, backupPin]).isTrusted(trust, host: TestCertificates.host))
    }

    @Test func acceptsBackupPin() {
        let trust = TestCertificates.trust(for: TestCertificates.good)
        #expect(validator(pins: [backupPin, TestCertificates.goodPin]).isTrusted(trust, host: TestCertificates.host))
    }

    @Test func rejectsValidChainWithWrongKey() {
        // Same trusted CA, different key: only the pin catches it.
        let trust = TestCertificates.trust(for: TestCertificates.other)
        #expect(!validator(pins: [TestCertificates.goodPin, backupPin]).isTrusted(trust, host: TestCertificates.host))
    }

    @Test func rejectsUntrustedChainEvenWithMatchingPin() {
        let trust = TestCertificates.trust(for: TestCertificates.good, anchored: false)
        #expect(!validator(pins: [TestCertificates.goodPin, backupPin]).isTrusted(trust, host: TestCertificates.host))
    }

    @Test func rejectsExpiredCertificate() throws {
        let shortLivedPin = try #require(SPKIHasher.pin(for: TestCertificates.shortLived))
        let afterExpiry = Date().addingTimeInterval(3 * 86_400)
        let trust = TestCertificates.trust(for: TestCertificates.shortLived, at: afterExpiry)
        #expect(!validator(pins: [shortLivedPin, backupPin]).isTrusted(trust, host: TestCertificates.host))
    }

    @Test func rejectsHostnameMismatch() {
        let trust = TestCertificates.trust(for: TestCertificates.good)
        #expect(!validator(pins: [TestCertificates.goodPin, backupPin]).isTrusted(trust, host: "evil.example"))
    }

    @Test func killSwitchDisablesPinsButNotSystemValidation() {
        let policy = PinningPolicy(pinnedHosts: [TestCertificates.host], pins: [TestCertificates.goodPin, backupPin])
        let disabled = RemoteSecurityConfig(version: 1, expiresAt: .distantFuture, pinning: .init(enabled: false, pins: []))
        #expect(policy.apply(disabled))

        let validator = PinValidator(policy: policy)
        #expect(validator.isTrusted(TestCertificates.trust(for: TestCertificates.other), host: TestCertificates.host))
        #expect(!validator.isTrusted(TestCertificates.trust(for: TestCertificates.good, anchored: false), host: TestCertificates.host))
    }

    @Test func remoteConfigUpdatesPinsAndIgnoresReplays() {
        let policy = PinningPolicy(pinnedHosts: [TestCertificates.host], pins: [TestCertificates.goodPin, backupPin])
        let rotated = RemoteSecurityConfig(
            version: 2, expiresAt: .distantFuture, pinning: .init(enabled: true, pins: [TestCertificates.otherPin, backupPin])
        )
        let older = RemoteSecurityConfig(version: 1, expiresAt: .distantFuture, pinning: .init(enabled: false, pins: []))

        #expect(policy.apply(rotated))
        #expect(!policy.apply(older))
        #expect(!policy.apply(rotated))
        #expect(policy.current.isEnforced)
        #expect(policy.current.pins == [TestCertificates.otherPin, backupPin])
    }

    @Test func delegateFailsClosedWithoutServerTrust() {
        let delegate = PinningDelegate(policy: PinningPolicy(pinnedHosts: [TestCertificates.host], pins: [backupPin]))
        let space = URLProtectionSpace(
            host: TestCertificates.host, port: 443, protocol: "https", realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        #expect(delegate.evaluate(space).0 == .cancelAuthenticationChallenge)
    }

    @Test func delegateLeavesOtherHostsAndMethodsToTheSystem() {
        let delegate = PinningDelegate(policy: PinningPolicy(pinnedHosts: [TestCertificates.host], pins: [backupPin]))
        let otherHost = URLProtectionSpace(
            host: "storage.example", port: 443, protocol: "https", realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        let basicAuth = URLProtectionSpace(
            host: TestCertificates.host, port: 443, protocol: "https", realm: nil,
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        #expect(delegate.evaluate(otherHost).0 == .performDefaultHandling)
        #expect(delegate.evaluate(basicAuth).0 == .performDefaultHandling)
    }
}

struct SignedConfigVerifierTests {
    private let signingKey = Curve25519.Signing.PrivateKey()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let pinA = Data(repeating: 1, count: 32).base64EncodedString()
    private let pinB = Data(repeating: 2, count: 32).base64EncodedString()

    private func verifier() throws -> SignedConfigVerifier {
        let now = now
        return try SignedConfigVerifier(publicKey: signingKey.publicKey.rawRepresentation, now: { now })
    }

    private func envelope(_ json: String, signedBy key: Curve25519.Signing.PrivateKey? = nil, tamper: Bool = false) throws -> Data {
        let payload = Data(json.utf8)
        let signature = try (key ?? signingKey).signature(for: payload)
        let sent = tamper ? Data(json.replacingOccurrences(of: "true", with: "false").utf8) : payload
        return try JSONSerialization.data(withJSONObject: [
            "payload": sent.base64EncodedString(),
            "signature": signature.base64EncodedString(),
        ])
    }

    private func config(enabled: Bool, pins: [String], expires: String = "2030-01-01T00:00:00Z") -> String {
        let list = pins.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"version":3,"expiresAt":"\#(expires)","pinning":{"enabled":\#(enabled),"pins":[\#(list)]}}"#
    }

    @Test func acceptsValidSignedConfig() throws {
        let result = try verifier().securityConfig(from: envelope(config(enabled: true, pins: [pinA, pinB])))
        #expect(result.version == 3)
        #expect(result.pinning == .init(enabled: true, pins: [pinA, pinB]))
    }

    @Test func acceptsKillSwitchWithoutPins() throws {
        let result = try verifier().securityConfig(from: envelope(config(enabled: false, pins: [])))
        #expect(result.pinning.enabled == false)
    }

    @Test func rejectsTamperedPayload() throws {
        let data = try envelope(config(enabled: true, pins: [pinA, pinB]), tamper: true)
        #expect(throws: SignedConfigError.invalidSignature) { try verifier().securityConfig(from: data) }
    }

    @Test func rejectsForeignSigningKey() throws {
        let data = try envelope(config(enabled: false, pins: []), signedBy: Curve25519.Signing.PrivateKey())
        #expect(throws: SignedConfigError.invalidSignature) { try verifier().securityConfig(from: data) }
    }

    @Test func rejectsExpiredConfig() throws {
        let data = try envelope(config(enabled: false, pins: [], expires: "2020-01-01T00:00:00Z"))
        #expect(throws: SignedConfigError.expired) { try verifier().securityConfig(from: data) }
    }

    @Test(arguments: [1, 2])
    func rejectsEnabledPinningWithTooFewOrInvalidPins(variant: Int) throws {
        let pins = variant == 1 ? [pinA] : [pinA, "not-a-pin"]
        let data = try envelope(config(enabled: true, pins: pins))
        #expect(throws: SignedConfigError.invalidPins) { try verifier().securityConfig(from: data) }
    }

    @Test func rejectsMalformedInput() throws {
        #expect(throws: SignedConfigError.malformed) { try verifier().verifiedPayload(from: Data("{}".utf8)) }
        let wrongShape = try envelope(#"{"hello":"world"}"#)
        #expect(throws: SignedConfigError.malformed) { try verifier().securityConfig(from: wrongShape) }
        #expect(throws: SignedConfigError.malformed) { try SignedConfigVerifier(publicKey: Data([1, 2, 3])) }
    }
}
