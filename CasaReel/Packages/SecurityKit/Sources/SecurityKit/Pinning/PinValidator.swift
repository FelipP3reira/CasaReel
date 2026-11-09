import Foundation
import Security

/// Validates a server trust: standard chain + hostname evaluation first, then the SPKI pins.
/// The system evaluation is never skipped, not even when the kill switch disables pinning.
struct PinValidator: Sendable {
    let policy: PinningPolicy

    func isTrusted(_ trust: SecTrust, host: String) -> Bool {
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        guard SecTrustEvaluateWithError(trust, nil) else { return false }
        let state = policy.current
        guard state.isEnforced else { return true }
        let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] ?? []
        // Any certificate in the validated chain may carry the pin (leaf or intermediate).
        return chain.contains { certificate in
            SPKIHasher.pin(for: certificate).map(state.pins.contains) ?? false
        }
    }
}
