import Foundation

/// Token pair returned by `/auth/apple` and `/auth/refresh` (`TokenPair` in openapi.yaml).
public struct TokenPair: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    /// Access token lifetime in seconds.
    public let expiresIn: Int

    public init(accessToken: String, refreshToken: String, expiresIn: Int) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
    }
}

public enum TokenError: Error, Equatable, Sendable {
    /// No session is stored on this device.
    case notAuthenticated
    /// The server answered `session_revoked`; local tokens were wiped.
    case sessionRevoked
    /// Refresh failed for a transient reason (network, 5xx); tokens are kept for a later retry.
    case refreshFailed
    case storageFailed
}

/// Failure reported by the network layer when calling `/auth/refresh`.
public enum TokenRefreshError: Error, Equatable, Sendable {
    /// `401` with problem code `session_revoked` (or an invalid refresh token).
    case sessionRevoked
    case transient
}

/// Calls `/auth/refresh` (implemented by `Networking` in P04).
public protocol TokenRefreshing: Sendable {
    func refresh(using refreshToken: String) async throws(TokenRefreshError) -> TokenPair
}

/// Session tokens for the network layer and the auth feature (implemented by `SecurityKit.TokenManager`).
public protocol AccessTokenProviding: Sendable {
    /// A non-expired access token, refreshing first when needed. Concurrent callers share one refresh.
    func validAccessToken() async throws(TokenError) -> String
    /// Called after the server rejected `token` with `401`; refreshes unless another caller already did.
    func refreshAfterRejection(of token: String) async throws(TokenError) -> String
    func store(_ pair: TokenPair) async throws(TokenError)
    /// Wipes tokens on sign-out.
    func clear() async
}
