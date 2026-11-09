import Foundation

/// Per-environment values injected at build time through `Config/*.xcconfig` and `Info.plist`.
public struct AppConfiguration: Sendable, Equatable {
    public enum Environment: String, Sendable {
        case debug
        case staging
        case release
    }

    public enum InfoKey {
        public static let environment = "CREnvironment"
        public static let apiBaseURL = "CRAPIBaseURL"
        public static let universalLinkHost = "CRUniversalLinkHost"
        public static let publicKeyPins = "CRPublicKeyPins"
        public static let configSigningPublicKey = "CRConfigSigningPublicKey"
    }

    /// Current + backup pins are required so a certificate rotation never bricks the app.
    public static let minimumPinCount = 2

    public let environment: Environment
    public let apiBaseURL: URL
    /// Host whose `https://<host>/app/...` links open screens in the app.
    public let universalLinkHost: String
    /// Base64 SHA-256 hashes of the API server's SubjectPublicKeyInfo (current + backup).
    public let publicKeyPins: [String]
    /// Raw Ed25519 public key that verifies signed remote configuration (kill switch, pin updates).
    public let configSigningPublicKey: Data

    public init(
        environment: Environment,
        apiBaseURL: URL,
        universalLinkHost: String,
        publicKeyPins: [String],
        configSigningPublicKey: Data
    ) {
        self.environment = environment
        self.apiBaseURL = apiBaseURL
        self.universalLinkHost = universalLinkHost
        self.publicKeyPins = publicKeyPins
        self.configSigningPublicKey = configSigningPublicKey
    }

    /// Reads and validates the configuration; only HTTPS base URLs and bare host names are accepted.
    public init(infoDictionary: [String: Any]) throws(AppConfigurationError) {
        guard let rawEnvironment = infoDictionary[InfoKey.environment] as? String else {
            throw .missingValue(InfoKey.environment)
        }
        guard let environment = Environment(rawValue: rawEnvironment) else {
            throw .invalidValue(InfoKey.environment)
        }
        guard let rawURL = infoDictionary[InfoKey.apiBaseURL] as? String else {
            throw .missingValue(InfoKey.apiBaseURL)
        }
        guard let url = URL(string: rawURL), url.scheme == "https", url.host() != nil else {
            throw .invalidValue(InfoKey.apiBaseURL)
        }
        guard let host = infoDictionary[InfoKey.universalLinkHost] as? String else {
            throw .missingValue(InfoKey.universalLinkHost)
        }
        guard host.wholeMatch(of: /[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/) != nil else {
            throw .invalidValue(InfoKey.universalLinkHost)
        }
        self.init(
            environment: environment,
            apiBaseURL: url,
            universalLinkHost: host,
            publicKeyPins: try Self.pins(from: infoDictionary),
            configSigningPublicKey: try Self.signingKey(from: infoDictionary)
        )
    }

    /// Pins are a comma-separated list; each one must decode to a 32-byte SHA-256 digest.
    private static func pins(from infoDictionary: [String: Any]) throws(AppConfigurationError) -> [String] {
        guard let raw = infoDictionary[InfoKey.publicKeyPins] as? String else {
            throw .missingValue(InfoKey.publicKeyPins)
        }
        let pins = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let valid = pins.allSatisfy { Data(base64Encoded: $0)?.count == 32 }
        guard valid, Set(pins).count >= minimumPinCount else {
            throw .invalidValue(InfoKey.publicKeyPins)
        }
        return pins
    }

    private static func signingKey(from infoDictionary: [String: Any]) throws(AppConfigurationError) -> Data {
        guard let raw = infoDictionary[InfoKey.configSigningPublicKey] as? String else {
            throw .missingValue(InfoKey.configSigningPublicKey)
        }
        guard let key = Data(base64Encoded: raw), key.count == 32 else {
            throw .invalidValue(InfoKey.configSigningPublicKey)
        }
        return key
    }
}

public enum AppConfigurationError: Error, Equatable, Sendable {
    case missingValue(String)
    case invalidValue(String)
}
