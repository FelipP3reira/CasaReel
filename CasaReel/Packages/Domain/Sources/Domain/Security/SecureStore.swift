import Foundation

/// How a stored secret is protected beyond `WhenUnlockedThisDeviceOnly`.
public enum SecureStoreProtection: Sendable, Equatable {
    case standard
    /// Every read requires Face ID / Touch ID; the item is invalidated if biometrics change.
    case biometry
}

/// Failures never carry secret values, keys or raw payloads.
public enum SecureStoreError: Error, Equatable, Sendable {
    case encodingFailed
    case decodingFailed
    /// The user cancelled or failed biometric authentication.
    case authenticationFailed
    /// The device is locked or the item cannot be read in the current state.
    case interactionNotAllowed
    case unexpectedStatus(Int32)
}

/// Secret storage (implemented by `SecurityKit` on top of the Keychain). Never back it with `UserDefaults` or files.
public protocol SecureStore: Sendable {
    func set(_ data: Data, for key: String, protection: SecureStoreProtection) throws(SecureStoreError)
    /// Returns `nil` when no item exists for `key`.
    func data(for key: String) throws(SecureStoreError) -> Data?
    func delete(_ key: String) throws(SecureStoreError)
    /// Removes every item owned by this store.
    func deleteAll() throws(SecureStoreError)
}

extension SecureStore {
    public func set(_ data: Data, for key: String) throws(SecureStoreError) {
        try set(data, for: key, protection: .standard)
    }

    public func set<Value: Encodable>(
        _ value: Value,
        for key: String,
        protection: SecureStoreProtection = .standard
    ) throws(SecureStoreError) {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw .encodingFailed
        }
        try set(data, for: key, protection: protection)
    }

    public func value<Value: Decodable>(_ type: Value.Type, for key: String) throws(SecureStoreError) -> Value? {
        guard let data = try data(for: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw .decodingFailed
        }
    }
}
