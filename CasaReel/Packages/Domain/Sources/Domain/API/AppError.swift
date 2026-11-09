import Foundation

/// RFC 9457 `application/problem+json` body (`Problem` in openapi.yaml).
public struct Problem: Codable, Sendable, Equatable {
    public let type: String
    public let title: String
    public let status: Int
    public let detail: String?
    /// Stable machine-readable code, e.g. `session_revoked`.
    public let code: String?
    /// Field validation messages (422).
    public let errors: [String: [String]]?
}

/// Every failure the API layer can surface. Messages shown to the user are chosen from `code`;
/// technical detail never reaches the UI.
public struct AppError: Error, Sendable, Equatable {
    public enum Code: String, Sendable {
        case sessionRevoked = "session_revoked"
        case unauthorized
        case paymentRequired = "payment_required"
        case forbidden
        case notFound = "not_found"
        case conflict
        case validation = "validation_failed"
        case rateLimited = "rate_limited"
        case server = "server_error"
        case offline
        case timeout
        case cancelled
        case invalidResponse = "invalid_response"
        case responseTooLarge = "response_too_large"
        case unexpectedContentType = "unexpected_content_type"
        case unknown
    }

    public let code: Code
    /// HTTP status, when the server answered.
    public let status: Int?
    /// Raw `Problem.code` from the server, kept for codes this app version doesn't know yet.
    public let problemCode: String?
    public let fieldErrors: [String: [String]]
    /// From `Retry-After` on 429/503.
    public let retryAfter: Duration?

    public init(
        _ code: Code,
        status: Int? = nil,
        problemCode: String? = nil,
        fieldErrors: [String: [String]] = [:],
        retryAfter: Duration? = nil
    ) {
        self.code = code
        self.status = status
        self.problemCode = problemCode
        self.fieldErrors = fieldErrors
        self.retryAfter = retryAfter
    }

    /// Maps an error response; a known `Problem.code` wins over the status.
    public init(status: Int, problem: Problem?, retryAfter: Duration? = nil) {
        let code = problem?.code.flatMap(Code.init(rawValue:)) ?? Self.code(forStatus: status)
        self.init(
            code,
            status: status,
            problemCode: problem?.code,
            fieldErrors: problem?.errors ?? [:],
            retryAfter: retryAfter
        )
    }

    static func code(forStatus status: Int) -> Code {
        switch status {
        case 401: .unauthorized
        case 402: .paymentRequired
        case 403: .forbidden
        case 404: .notFound
        case 409: .conflict
        case 400, 422: .validation
        case 429: .rateLimited
        case 500...599: .server
        default: .unknown
        }
    }

    /// Worth retrying (for idempotent requests): the same request may succeed later.
    public var isTransient: Bool {
        switch code {
        case .rateLimited, .offline, .timeout: true
        case .server: status.map { [500, 502, 503, 504].contains($0) } ?? true
        default: false
        }
    }
}
