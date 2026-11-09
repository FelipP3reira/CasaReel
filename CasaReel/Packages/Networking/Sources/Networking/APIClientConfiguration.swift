import Foundation

public struct APIClientConfiguration: Sendable {
    public let baseURL: URL
    /// e.g. `CasaReel-iOS/0.1.0 (1; iOS 17.5)`.
    public let userAgent: String
    /// Value of `Accept-Language`, read per request so a language change applies immediately.
    public let acceptLanguage: @Sendable () -> String
    /// Value of `X-Device-Risk` (see `IntegritySignals`).
    public let deviceRisk: @Sendable () -> String
    /// Larger bodies are aborted mid-download; the API never returns more than a page of JSON.
    public let maxResponseBytes: Int
    public let retry: RetryPolicy

    public init(
        baseURL: URL,
        userAgent: String,
        acceptLanguage: @escaping @Sendable () -> String = { Locale.preferredLanguages.prefix(3).joined(separator: ", ") },
        deviceRisk: @escaping @Sendable () -> String = { "v1;none" },
        maxResponseBytes: Int = 5 * 1024 * 1024,
        retry: RetryPolicy = RetryPolicy()
    ) {
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.acceptLanguage = acceptLanguage
        self.deviceRisk = deviceRisk
        self.maxResponseBytes = maxResponseBytes
        self.retry = retry
    }
}

extension URLSessionConfiguration {
    /// Ephemeral session for the API: no disk cache, no cookies, explicit timeouts, TLS 1.2+.
    public static var casaReelAPI: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.waitsForConnectivity = true
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return configuration
    }
}

/// Exponential backoff with full jitter, for transient errors on retryable requests only.
public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelay: Duration
    public let maxDelay: Duration
    /// Upper bound for a server-provided `Retry-After`.
    public let maxRetryAfter: Duration
    private let random: @Sendable () -> Double

    public init(
        maxAttempts: Int = 3,
        baseDelay: Duration = .milliseconds(500),
        maxDelay: Duration = .seconds(8),
        maxRetryAfter: Duration = .seconds(60),
        random: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.maxRetryAfter = maxRetryAfter
        self.random = random
    }

    /// Delay before attempt `attempt + 1`; `Retry-After` wins when present.
    public func delay(afterAttempt attempt: Int, retryAfter: Duration?) -> Duration {
        if let retryAfter { return min(retryAfter, maxRetryAfter) }
        let exponential = baseDelay * (1 << max(attempt - 1, 0))
        return min(exponential, maxDelay) * random()
    }
}
