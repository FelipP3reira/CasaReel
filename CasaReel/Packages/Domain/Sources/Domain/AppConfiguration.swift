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
    }

    public let environment: Environment
    public let apiBaseURL: URL
    /// Host whose `https://<host>/app/...` links open screens in the app.
    public let universalLinkHost: String

    public init(environment: Environment, apiBaseURL: URL, universalLinkHost: String) {
        self.environment = environment
        self.apiBaseURL = apiBaseURL
        self.universalLinkHost = universalLinkHost
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
        self.init(environment: environment, apiBaseURL: url, universalLinkHost: host)
    }
}

public enum AppConfigurationError: Error, Equatable, Sendable {
    case missingValue(String)
    case invalidValue(String)
}
