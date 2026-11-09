import Domain
import Foundation
import Security

/// Generic-password Keychain storage. Items are `WhenUnlockedThisDeviceOnly`, never synced to iCloud
/// and never included in backups that restore to another device.
public struct KeychainStore: SecureStore {
    /// Groups the items of one store; tests use a unique service to stay isolated.
    public let service: String

    public init(service: String = "br.com.casareel.app.secure") {
        self.service = service
    }

    public func set(_ data: Data, for key: String, protection: SecureStoreProtection) throws(SecureStoreError) {
        // Delete + add (instead of update) so a change of protection also changes the access control.
        try delete(key)
        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        query[kSecAttrSynchronizable as String] = false
        switch protection {
        case .standard:
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .biometry:
            query[kSecAttrAccessControl as String] = try Self.biometryAccessControl()
        }
        try Self.check(SecItemAdd(query as CFDictionary, nil))
    }

    public func data(for key: String) throws(SecureStoreError) -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try Self.check(status)
        guard let data = result as? Data else { throw .decodingFailed }
        return data
    }

    public func delete(_ key: String) throws(SecureStoreError) {
        try Self.checkDeletion(SecItemDelete(baseQuery(for: key) as CFDictionary))
    }

    public func deleteAll() throws(SecureStoreError) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        try Self.checkDeletion(SecItemDelete(query as CFDictionary))
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// Reads require the currently enrolled biometrics; enrolling a new finger/face invalidates the item.
    static func biometryAccessControl() throws(SecureStoreError) -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            error?.release()
            throw .unexpectedStatus(errSecParam)
        }
        return control
    }

    private static func checkDeletion(_ status: OSStatus) throws(SecureStoreError) {
        guard status != errSecItemNotFound else { return }
        try check(status)
    }

    static func check(_ status: OSStatus) throws(SecureStoreError) {
        switch status {
        case errSecSuccess:
            return
        case errSecUserCanceled, errSecAuthFailed:
            throw .authenticationFailed
        case errSecInteractionNotAllowed:
            throw .interactionNotAllowed
        default:
            throw .unexpectedStatus(status)
        }
    }
}
