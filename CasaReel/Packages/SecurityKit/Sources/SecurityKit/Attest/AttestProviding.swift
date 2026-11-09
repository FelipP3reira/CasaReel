import DeviceCheck
import Foundation

public enum AttestProviderError: Error, Equatable, Sendable {
    /// The key no longer exists or was invalidated (reinstall, restore); a new one must be attested.
    case invalidKey
    case failed
}

/// Abstraction over `DCAppAttestService` so the client can be tested with a mock.
public protocol AttestProviding: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws(AttestProviderError) -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws(AttestProviderError) -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws(AttestProviderError) -> Data
}

/// Production provider. Unsupported on the Simulator and on devices without the Secure Enclave.
public struct DeviceAttestProvider: AttestProviding {
    public init() {}

    public var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    public func generateKey() async throws(AttestProviderError) -> String {
        try await mapped { try await DCAppAttestService.shared.generateKey() }
    }

    public func attestKey(_ keyId: String, clientDataHash: Data) async throws(AttestProviderError) -> Data {
        try await mapped { try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash) }
    }

    public func generateAssertion(_ keyId: String, clientDataHash: Data) async throws(AttestProviderError) -> Data {
        try await mapped { try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash) }
    }

    private func mapped<Value>(_ operation: () async throws -> Value) async throws(AttestProviderError) -> Value {
        do {
            return try await operation()
        } catch let error as DCError where error.code == .invalidKey {
            throw .invalidKey
        } catch {
            throw .failed
        }
    }
}
