import Foundation
import os

/// Thread-safe pin set read by `PinningDelegate` on every TLS handshake. Starts with the pins bundled in
/// `AppConfiguration` and can only be changed by a remote config whose Ed25519 signature was verified.
public final class PinningPolicy: Sendable {
    struct State: Equatable {
        var pins: Set<String>
        var isEnforced: Bool
        /// Highest remote config version applied; older or replayed configs are ignored.
        var version: Int
    }

    public let pinnedHosts: Set<String>
    private let state: OSAllocatedUnfairLock<State>

    public init(pinnedHosts: Set<String>, pins: [String]) {
        self.pinnedHosts = Set(pinnedHosts.map { $0.lowercased() })
        state = OSAllocatedUnfairLock(initialState: State(pins: Set(pins), isEnforced: true, version: 0))
    }

    var current: State {
        state.withLock { $0 }
    }

    func appliesTo(host: String) -> Bool {
        pinnedHosts.contains(host.lowercased())
    }

    /// Applies a verified config. Returns `false` when it is not newer than the one in use.
    @discardableResult
    public func apply(_ config: RemoteSecurityConfig) -> Bool {
        state.withLock { state in
            guard config.version > state.version else { return false }
            state = State(pins: Set(config.pinning.pins), isEnforced: config.pinning.enabled, version: config.version)
            return true
        }
    }
}
