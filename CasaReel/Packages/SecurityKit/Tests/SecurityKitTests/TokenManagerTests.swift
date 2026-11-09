import Domain
import Foundation
import Testing
@testable import SecurityKit

struct TokenManagerTests {
    private let store = InMemorySecureStore()
    private let clock = TestClock()

    private func manager(_ refresher: MockRefresher) -> TokenManager {
        let clock = clock
        return TokenManager(store: store, refresher: refresher, leeway: 60, now: { clock.now })
    }

    private let initial = TokenPair(accessToken: "access-0", refreshToken: "refresh-0", expiresIn: 3600)

    @Test func throwsWhenNotAuthenticated() async {
        let tokens = manager(MockRefresher())
        await #expect(throws: TokenError.notAuthenticated) { try await tokens.validAccessToken() }
    }

    @Test func returnsStoredTokenWithoutRefreshing() async throws {
        let refresher = MockRefresher()
        let tokens = manager(refresher)
        try await tokens.store(initial)

        #expect(try await tokens.validAccessToken() == "access-0")
        #expect(await refresher.calls == 0)
    }

    @Test func tokensSurviveAppRestartThroughSecureStore() async throws {
        try await manager(MockRefresher()).store(initial)
        #expect(try await manager(MockRefresher()).validAccessToken() == "access-0")
    }

    @Test func concurrentCallersShareASingleRefresh() async throws {
        let refresher = MockRefresher()
        let tokens = manager(refresher)
        try await tokens.store(initial)
        clock.advance(by: 3600 - 30)  // inside the leeway window

        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<20 {
                group.addTask { try await tokens.validAccessToken() }
            }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }

        #expect(await refresher.calls == 1)
        #expect(Set(results) == ["access-1"])
    }

    @Test func refreshAfterRejectionSkipsWhenAnotherCallerAlreadyRefreshed() async throws {
        let refresher = MockRefresher()
        let tokens = manager(refresher)
        try await tokens.store(initial)

        #expect(try await tokens.refreshAfterRejection(of: "access-0") == "access-1")
        // A late 401 for the old token must not trigger a second refresh.
        #expect(try await tokens.refreshAfterRejection(of: "access-0") == "access-1")
        #expect(await refresher.calls == 1)
    }

    @Test func revokedSessionWipesStorageAndEmitsEvent() async throws {
        let tokens = manager(MockRefresher(outcome: .revoked))
        try await tokens.store(initial)
        clock.advance(by: 7200)

        await #expect(throws: TokenError.sessionRevoked) { try await tokens.validAccessToken() }
        #expect(store.deleteAllCalls == 1)
        #expect(store.keys.isEmpty)

        var iterator = tokens.events.makeAsyncIterator()
        #expect(await iterator.next() == .revoked)
        await #expect(throws: TokenError.notAuthenticated) { try await tokens.validAccessToken() }
    }

    @Test func transientFailureKeepsTokensForRetry() async throws {
        let tokens = manager(MockRefresher(outcome: .transient))
        try await tokens.store(initial)
        clock.advance(by: 7200)

        await #expect(throws: TokenError.refreshFailed) { try await tokens.validAccessToken() }
        #expect(store.keys == [TokenManager.storageKey])
    }

    @Test func clearRemovesTokens() async throws {
        let tokens = manager(MockRefresher())
        try await tokens.store(initial)
        await tokens.clear()

        #expect(store.keys.isEmpty)
        await #expect(throws: TokenError.notAuthenticated) { try await tokens.validAccessToken() }
    }

    @Test func signOutDuringRefreshDoesNotResurrectSession() async throws {
        let refresher = MockRefresher(delay: .milliseconds(200))
        let tokens = manager(refresher)
        try await tokens.store(initial)
        clock.advance(by: 7200)

        let pending = Task { try await tokens.validAccessToken() }
        try await Task.sleep(for: .milliseconds(50))
        await tokens.clear()

        await #expect(throws: TokenError.self) { try await pending.value }
        #expect(store.keys.isEmpty)
    }
}
