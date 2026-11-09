import Observation

public enum SessionState: Sendable, Equatable {
    case signedOut
    case signedIn
    /// The server invalidated the session (e.g. `session_revoked`); the user must sign in again.
    case revoked
}

/// Global session state. Until P05 adds real authentication, only the placeholder sign-in changes it.
@Observable
@MainActor
public final class SessionStore {
    public private(set) var state: SessionState

    public init(state: SessionState = .signedOut) {
        self.state = state
    }

    public func signIn() {
        state = .signedIn
    }

    public func signOut() {
        state = .signedOut
    }

    public func revoke() {
        state = .revoked
    }
}
