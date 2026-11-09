import Domain
import Foundation
import Security
import Testing
@testable import SecurityKit

/// Package tests run in a host process without the Keychain entitlement (errSecMissingEntitlement, -34018).
/// The real-Keychain suite runs only where access exists (an app-hosted test target or a device).
enum KeychainAvailability {
    static let isAvailable: Bool = {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "br.com.casareel.tests.probe",
            kSecAttrAccount as String: UUID().uuidString,
            kSecValueData as String: Data([1]),
        ]
        let status = SecItemAdd(probe as CFDictionary, nil)
        SecItemDelete(probe as CFDictionary)
        return status != errSecMissingEntitlement
    }()
}

/// Runs against the real Keychain; every test uses its own service and wipes it afterwards.
@Suite(.enabled(if: KeychainAvailability.isAvailable, "Keychain entitlement unavailable in this test host"))
final class KeychainStoreTests {
    private let store = KeychainStore(service: "br.com.casareel.tests.\(UUID().uuidString)")

    deinit {
        try? store.deleteAll()
    }

    private struct Profile: Codable, Equatable {
        let name: String
        let count: Int
    }

    @Test func storesAndReadsData() throws {
        try store.set(Data("secret".utf8), for: "a")
        #expect(try store.data(for: "a") == Data("secret".utf8))
    }

    @Test func missingItemIsNil() throws {
        #expect(try store.data(for: "missing") == nil)
    }

    @Test func overwritesExistingItem() throws {
        try store.set(Data("one".utf8), for: "a")
        try store.set(Data("two".utf8), for: "a")
        #expect(try store.data(for: "a") == Data("two".utf8))
    }

    @Test func deletesItemAndToleratesMissingOnes() throws {
        try store.set(Data("x".utf8), for: "a")
        try store.delete("a")
        try store.delete("a")
        #expect(try store.data(for: "a") == nil)
    }

    @Test func deleteAllOnlyTouchesItsOwnService() throws {
        let neighbour = KeychainStore(service: "br.com.casareel.tests.\(UUID().uuidString)")
        defer { try? neighbour.deleteAll() }
        try store.set(Data("1".utf8), for: "a")
        try store.set(Data("2".utf8), for: "b")
        try neighbour.set(Data("3".utf8), for: "a")

        try store.deleteAll()

        #expect(try store.data(for: "a") == nil)
        #expect(try store.data(for: "b") == nil)
        #expect(try neighbour.data(for: "a") == Data("3".utf8))
    }

    @Test func roundTripsCodableValues() throws {
        try store.set(Profile(name: "Ana", count: 3), for: "profile")
        #expect(try store.value(Profile.self, for: "profile") == Profile(name: "Ana", count: 3))
        #expect(try store.value(Profile.self, for: "absent") == nil)
    }

    @Test func undecodableValueThrowsWithoutLeakingContent() throws {
        try store.set(Data("not json".utf8), for: "profile")
        #expect(throws: SecureStoreError.decodingFailed) {
            try store.value(Profile.self, for: "profile")
        }
    }

    @Test func itemsAreDeviceOnlyAndNotSynchronized() throws {
        try store.set(Data("x".utf8), for: "attrs")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrAccount as String: "attrs",
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        let attributes = try #require(result as? [String: Any])
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect((attributes[kSecAttrSynchronizable as String] as? Bool ?? false) == false)
    }
}

/// Keychain logic that doesn't need the entitlement.
struct KeychainPolicyTests {
    @Test func createsBiometryAccessControl() throws {
        _ = try KeychainStore.biometryAccessControl()
    }

    @Test(arguments: [
        (errSecUserCanceled, SecureStoreError.authenticationFailed),
        (errSecAuthFailed, .authenticationFailed),
        (errSecInteractionNotAllowed, .interactionNotAllowed),
        (errSecDuplicateItem, .unexpectedStatus(errSecDuplicateItem)),
    ])
    func mapsStatusesToErrors(status: OSStatus, expected: SecureStoreError) {
        #expect(throws: expected) { try KeychainStore.check(status) }
    }
}
