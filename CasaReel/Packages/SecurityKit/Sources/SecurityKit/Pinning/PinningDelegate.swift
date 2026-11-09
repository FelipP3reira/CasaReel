import Foundation

/// `URLSessionDelegate` that pins the API host. Fails closed: a mismatch cancels the challenge.
/// Hosts outside `PinningPolicy.pinnedHosts` (e.g. storage upload URLs) get the default system validation.
public final class PinningDelegate: NSObject, URLSessionDelegate, Sendable {
    private let validator: PinValidator
    private let logger = SecureLogger(category: "pinning")

    public init(policy: PinningPolicy) {
        validator = PinValidator(policy: policy)
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        evaluate(challenge.protectionSpace)
    }

    func evaluate(_ space: URLProtectionSpace) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard
            space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            validator.policy.appliesTo(host: space.host)
        else {
            return (.performDefaultHandling, nil)
        }
        guard let trust = space.serverTrust, validator.isTrusted(trust, host: space.host) else {
            logger.error("Server trust rejected by pinning")
            return (.cancelAuthenticationChallenge, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }
}
