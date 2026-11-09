import CryptoKit
import Domain
import Foundation

/// Security settings delivered by the server as a signed envelope.
public struct RemoteSecurityConfig: Codable, Sendable, Equatable {
    public struct Pinning: Codable, Sendable, Equatable {
        /// `false` is the emergency kill switch; system certificate validation stays on regardless.
        public let enabled: Bool
        public let pins: [String]

        public init(enabled: Bool, pins: [String]) {
            self.enabled = enabled
            self.pins = pins
        }
    }

    /// Monotonic; protects against replay of an older (e.g. pinning-disabled) config.
    public let version: Int
    public let expiresAt: Date
    public let pinning: Pinning

    public init(version: Int, expiresAt: Date, pinning: Pinning) {
        self.version = version
        self.expiresAt = expiresAt
        self.pinning = pinning
    }
}

public enum SignedConfigError: Error, Equatable, Sendable {
    case malformed
    case invalidSignature
    case expired
    /// Pinning enabled without the minimum number of valid pins.
    case invalidPins
}

/// Verifies Ed25519-signed payloads with the public key bundled in the app (the private key stays offline).
/// Envelope: `{"payload": base64(JSON bytes), "signature": base64(Ed25519(payload bytes))}`.
public struct SignedConfigVerifier: Sendable {
    struct Envelope: Decodable {
        let payload: Data
        let signature: Data
    }

    private let publicKey: Curve25519.Signing.PublicKey
    private let now: @Sendable () -> Date

    public init(publicKey: Data, now: @escaping @Sendable () -> Date = Date.init) throws(SignedConfigError) {
        do {
            self.publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        } catch {
            throw .malformed
        }
        self.now = now
    }

    /// Returns the payload bytes only if the signature matches; reusable for templates and model packages.
    public func verifiedPayload(from envelope: Data) throws(SignedConfigError) -> Data {
        let decoded: Envelope
        do {
            decoded = try JSONDecoder().decode(Envelope.self, from: envelope)
        } catch {
            throw .malformed
        }
        guard publicKey.isValidSignature(decoded.signature, for: decoded.payload) else {
            throw .invalidSignature
        }
        return decoded.payload
    }

    public func securityConfig(from envelope: Data) throws(SignedConfigError) -> RemoteSecurityConfig {
        let payload = try verifiedPayload(from: envelope)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let config: RemoteSecurityConfig
        do {
            config = try decoder.decode(RemoteSecurityConfig.self, from: payload)
        } catch {
            throw .malformed
        }
        guard config.expiresAt > now() else { throw .expired }
        if config.pinning.enabled {
            let valid = config.pinning.pins.allSatisfy { Data(base64Encoded: $0)?.count == 32 }
            guard valid, Set(config.pinning.pins).count >= AppConfiguration.minimumPinCount else { throw .invalidPins }
        }
        return config
    }
}
