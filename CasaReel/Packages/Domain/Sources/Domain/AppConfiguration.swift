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
    }

    public let environment: Environment
    public let apiBaseURL: URL

    public init(environment: Environment, apiBaseURL: URL) {
        self.environment = environment
        self.apiBaseURL = apiBaseURL
    }

    /// Reads and validates the configuration; only HTTPS base URLs are accepted.
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
        self.init(environment: environment, apiBaseURL: url)
    }
}

public enum AppConfigurationError: Error, Equatable, Sendable {
    case missingValue(String)
    case invalidValue(String)
}
