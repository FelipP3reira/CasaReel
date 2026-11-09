import Foundation
import OSLog

/// `os.Logger` wrapper for the security-sensitive layers. Messages are redacted (tokens, e-mails, JWTs)
/// and then logged as `.private`, so they are hidden in production logs unless a profile unlocks them.
public struct SecureLogger: Sendable {
    private let logger: Logger

    public init(subsystem: String = "br.com.casareel.app", category: String) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    public func debug(_ message: String) {
        logger.debug("\(Self.redact(message), privacy: .private)")
    }

    public func info(_ message: String) {
        logger.info("\(Self.redact(message), privacy: .private)")
    }

    public func notice(_ message: String) {
        logger.notice("\(Self.redact(message), privacy: .private)")
    }

    public func error(_ message: String) {
        logger.error("\(Self.redact(message), privacy: .private)")
    }

    static let placeholder = "<redacted>"

    /// Replaces secrets with a placeholder. Exposed for tests and for code that must log free text.
    public static func redact(_ message: String) -> String {
        // Bearer and JWT first, so a `token: Bearer …` pair never leaves the value half-redacted.
        message
            // Authorization headers and bare bearer tokens.
            .replacing(/(?i)bearer\s+[A-Za-z0-9\-._~+\/]+=*/, with: placeholder)
            // JWTs (header.payload.signature).
            .replacing(/eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]*/, with: placeholder)
            // `key=value` / `"key": "value"` pairs for secret-looking keys; the key name is kept.
            .replacing(/(?i)(access_?token|refresh_?token|token|password|secret|api_?key)("?\s*[:=]\s*"?)[^\s",&}]+/) {
                "\($0.output.1)\($0.output.2)\(placeholder)"
            }
            .replacing(/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/, with: placeholder)
    }
}
