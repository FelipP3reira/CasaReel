import Domain
import Foundation
import os
@testable import SecurityKit

/// In-memory `SecureStore` for tests that don't exercise the real Keychain.
final class InMemorySecureStore: SecureStore {
    private let items = OSAllocatedUnfairLock(initialState: [String: Data]())
    private let deleteAllCount = OSAllocatedUnfairLock(initialState: 0)

    var keys: Set<String> { items.withLock { Set($0.keys) } }
    var deleteAllCalls: Int { deleteAllCount.withLock { $0 } }

    func set(_ data: Data, for key: String, protection: SecureStoreProtection) throws(SecureStoreError) {
        items.withLock { $0[key] = data }
    }

    func data(for key: String) throws(SecureStoreError) -> Data? {
        items.withLock { $0[key] }
    }

    func delete(_ key: String) throws(SecureStoreError) {
        _ = items.withLock { $0.removeValue(forKey: key) }
    }

    func deleteAll() throws(SecureStoreError) {
        items.withLock { $0.removeAll() }
        deleteAllCount.withLock { $0 += 1 }
    }
}

/// Scriptable `/auth/refresh`: counts calls and waits a little so concurrent callers overlap.
actor MockRefresher: TokenRefreshing {
    enum Outcome {
        case success
        case revoked
        case transient
    }

    private(set) var calls = 0
    private let outcome: Outcome
    private let delay: Duration

    init(outcome: Outcome = .success, delay: Duration = .milliseconds(50)) {
        self.outcome = outcome
        self.delay = delay
    }

    func refresh(using refreshToken: String) async throws(TokenRefreshError) -> TokenPair {
        calls += 1
        let call = calls
        try? await Task.sleep(for: delay)
        switch outcome {
        case .success:
            return TokenPair(accessToken: "access-\(call)", refreshToken: "refresh-\(call)", expiresIn: 3600)
        case .revoked:
            throw .sessionRevoked
        case .transient:
            throw .transient
        }
    }
}

/// Mutable clock for expiry tests.
final class TestClock: Sendable {
    private let current: OSAllocatedUnfairLock<Date>

    init(_ date: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = OSAllocatedUnfairLock(initialState: date)
    }

    var now: Date { current.withLock { $0 } }

    func advance(by interval: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

final class MockAttestProvider: AttestProviding {
    private struct State {
        var generatedKeys = 0
        var attestations = 0
        var assertions: [Data] = []
        var invalidKeyOnce = false
    }

    let isSupported: Bool
    private let failAssertions: Bool
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(isSupported: Bool = true, failAssertions: Bool = false, invalidKeyOnce: Bool = false) {
        self.isSupported = isSupported
        self.failAssertions = failAssertions
        state.withLock { $0.invalidKeyOnce = invalidKeyOnce }
    }

    var generatedKeys: Int { state.withLock { $0.generatedKeys } }
    var lastClientDataHash: Data? { state.withLock { $0.assertions.last } }

    func generateKey() async throws(AttestProviderError) -> String {
        let count = state.withLock { state in
            state.generatedKeys += 1
            return state.generatedKeys
        }
        try? await Task.sleep(for: .milliseconds(20))
        return "key-\(count)"
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws(AttestProviderError) -> Data {
        state.withLock { $0.attestations += 1 }
        return Data("attestation-\(keyId)".utf8)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws(AttestProviderError) -> Data {
        if failAssertions { throw .failed }
        let invalid = state.withLock { state in
            defer { state.invalidKeyOnce = false }
            return state.invalidKeyOnce
        }
        if invalid { throw .invalidKey }
        state.withLock { $0.assertions.append(clientDataHash) }
        return Data("assertion-\(keyId)".utf8)
    }
}

actor MockAttestServer: AttestServerAPI {
    private(set) var registeredKeys: [String] = []
    private var challenges = 0

    func challenge() async throws -> String {
        challenges += 1
        return "challenge-\(challenges)"
    }

    func register(keyId: String, attestationObject: Data, challenge: String) async throws {
        registeredKeys.append(keyId)
    }
}
