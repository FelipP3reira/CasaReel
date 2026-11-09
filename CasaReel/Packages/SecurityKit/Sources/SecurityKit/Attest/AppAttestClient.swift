import CryptoKit
import Domain
import Foundation

/// `/attest/challenge` and `/attest/register` (implemented by `Networking` in P04).
public protocol AttestServerAPI: Sendable {
    /// A single-use challenge issued by the server.
    func challenge() async throws -> String
    func register(keyId: String, attestationObject: Data, challenge: String) async throws
}

/// Header to attach to a sensitive request.
public struct AttestHeader: Sendable, Equatable {
    public static let assertionName = "X-App-Attest-Assertion"
    /// Sent instead of an assertion so the server treats the request as higher risk.
    public static let statusName = "X-App-Attest-Status"

    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }

    static func unavailable(_ reason: AttestUnavailableReason) -> AttestHeader {
        AttestHeader(name: statusName, value: reason.rawValue)
    }
}

public enum AttestUnavailableReason: String, Sendable {
    /// `DCAppAttestService.isSupported == false` (Simulator, old hardware).
    case unsupported
    /// Supported, but key generation, attestation or the server round trip failed.
    case failed
}

/// App Attest flow: generate a Secure Enclave key once, attest it with the server and sign sensitive
/// requests with assertions over `SHA-256(body || challenge)`. Never throws: failure becomes a risk header.
public actor AppAttestClient {
    struct AssertionPayload: Codable {
        let keyId: String
        let challenge: String
        let assertion: Data
    }

    static let keyIdStorageKey = "attest.keyId"

    private let provider: any AttestProviding
    private let server: any AttestServerAPI
    /// Use a store separate from the session one: the attested key belongs to the device, not to the session.
    private let store: any SecureStore
    private let logger = SecureLogger(category: "attest")
    private var registration: Task<String, any Error>?

    public init(provider: any AttestProviding, server: any AttestServerAPI, store: any SecureStore) {
        self.provider = provider
        self.server = server
        self.store = store
    }

    public func header(forBody body: Data) async -> AttestHeader {
        guard provider.isSupported else { return .unavailable(.unsupported) }
        do {
            return try await assertionHeader(forBody: body)
        } catch AttestProviderError.invalidKey {
            // The stored key is gone (e.g. app restored on a new device): attest a fresh one once.
            try? store.delete(Self.keyIdStorageKey)
            return (try? await assertionHeader(forBody: body)) ?? .unavailable(.failed)
        } catch {
            logger.error("App Attest assertion failed: \(String(describing: error))")
            return .unavailable(.failed)
        }
    }

    private func assertionHeader(forBody body: Data) async throws -> AttestHeader {
        let keyId = try await registeredKeyId()
        let challenge = try await server.challenge()
        let clientDataHash = Self.clientDataHash(body: body, challenge: challenge)
        let assertion = try await provider.generateAssertion(keyId, clientDataHash: clientDataHash)
        let payload = AssertionPayload(keyId: keyId, challenge: challenge, assertion: assertion)
        let value = try JSONEncoder().encode(payload).base64EncodedString()
        return AttestHeader(name: AttestHeader.assertionName, value: value)
    }

    private func registeredKeyId() async throws -> String {
        if let data = try store.data(for: Self.keyIdStorageKey), let keyId = String(data: data, encoding: .utf8) {
            return keyId
        }
        let task = registration ?? Task { try await register() }
        registration = task
        defer { registration = nil }
        return try await task.value
    }

    private func register() async throws -> String {
        let keyId = try await provider.generateKey()
        let challenge = try await server.challenge()
        let attestation = try await provider.attestKey(keyId, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))
        try await server.register(keyId: keyId, attestationObject: attestation, challenge: challenge)
        // Persist only after the server accepted the key, so a failed registration is retried next time.
        try store.set(Data(keyId.utf8), for: Self.keyIdStorageKey)
        return keyId
    }

    static func clientDataHash(body: Data, challenge: String) -> Data {
        Data(SHA256.hash(data: body + Data(challenge.utf8)))
    }
}
