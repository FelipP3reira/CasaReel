import Domain
import Foundation

public enum SessionEvent: Sendable, Equatable {
    /// The server revoked the session; tokens are already wiped and the UI must return to sign-in.
    case revoked
}

/// Owns the session tokens. They live only in the Keychain (plus an in-memory copy while the app runs).
public actor TokenManager: AccessTokenProviding {
    struct StoredTokens: Codable, Equatable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    static let storageKey = "auth.tokens"

    /// Emits session events for the global session state; the app has a single consumer.
    public nonisolated let events: AsyncStream<SessionEvent>

    private let secureStore: any SecureStore
    private let refresher: any TokenRefreshing
    private let now: @Sendable () -> Date
    /// Refresh slightly before expiry so a token never expires in flight.
    private let leeway: TimeInterval
    private let eventContinuation: AsyncStream<SessionEvent>.Continuation
    private var cached: StoredTokens?
    /// The single in-flight refresh; concurrent callers await it instead of starting another.
    private var refreshTask: Task<StoredTokens, any Error>?

    public init(
        store: any SecureStore,
        refresher: any TokenRefreshing,
        leeway: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.secureStore = store
        self.refresher = refresher
        self.leeway = leeway
        self.now = now
        (events, eventContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    public func validAccessToken() async throws(TokenError) -> String {
        let tokens = try loadTokens()
        guard tokens.expiresAt.timeIntervalSince(now()) <= leeway else { return tokens.accessToken }
        return try await refresh(tokens).accessToken
    }

    public func refreshAfterRejection(of token: String) async throws(TokenError) -> String {
        let tokens = try loadTokens()
        guard tokens.accessToken == token else { return tokens.accessToken }
        return try await refresh(tokens).accessToken
    }

    public func store(_ pair: TokenPair) throws(TokenError) {
        let tokens = StoredTokens(
            accessToken: pair.accessToken,
            refreshToken: pair.refreshToken,
            expiresAt: now().addingTimeInterval(TimeInterval(pair.expiresIn))
        )
        do {
            try secureStore.set(tokens, for: Self.storageKey)
        } catch {
            throw .storageFailed
        }
        cached = tokens
    }

    public func clear() {
        refreshTask?.cancel()
        refreshTask = nil
        cached = nil
        try? secureStore.delete(Self.storageKey)
    }

    private func loadTokens() throws(TokenError) -> StoredTokens {
        if let cached { return cached }
        let stored: StoredTokens?
        do {
            stored = try secureStore.value(StoredTokens.self, for: Self.storageKey)
        } catch {
            throw .storageFailed
        }
        guard let stored else { throw .notAuthenticated }
        cached = stored
        return stored
    }

    private func refresh(_ tokens: StoredTokens) async throws(TokenError) -> StoredTokens {
        let task = refreshTask ?? startRefresh(using: tokens.refreshToken)
        // Only clear the slot if it still holds this task: after sign-out + sign-in a newer refresh may own it.
        defer { if refreshTask == task { refreshTask = nil } }
        do {
            return try await task.value
        } catch let error as TokenError {
            throw error
        } catch {
            throw .refreshFailed
        }
    }

    private func startRefresh(using refreshToken: String) -> Task<StoredTokens, any Error> {
        let task = Task { try await performRefresh(using: refreshToken) }
        refreshTask = task
        return task
    }

    private func performRefresh(using refreshToken: String) async throws(TokenError) -> StoredTokens {
        let pair: TokenPair
        do {
            pair = try await refresher.refresh(using: refreshToken)
        } catch .sessionRevoked {
            revokeSession()
            throw .sessionRevoked
        } catch {
            throw .refreshFailed
        }
        // Signed out while the request was in flight: don't resurrect the session.
        guard !Task.isCancelled else { throw .notAuthenticated }
        // Rotation: only the newest refresh token is kept; the server detects reuse of older ones.
        try store(pair)
        guard let cached else { throw .storageFailed }
        return cached
    }

    private func revokeSession() {
        cached = nil
        try? secureStore.deleteAll()
        eventContinuation.yield(.revoked)
    }
}
