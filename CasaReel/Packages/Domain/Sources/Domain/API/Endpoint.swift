import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"

    /// Safe to repeat without side effects beyond the first call (RFC 9110).
    public var isIdempotent: Bool {
        self != .post && self != .patch
    }
}

/// Response type for endpoints that answer `202`/`204` without a body worth decoding.
public struct EmptyResponse: Decodable, Sendable, Equatable {
    public init() {}
}

/// A typed API call. Paths are built from fixed segments and UUIDs only, never from free text,
/// so user input can't alter the route; free text goes in the JSON body or encoded query items.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public let name: String
    public let method: HTTPMethod
    public let pathSegments: [String]
    public let queryItems: [URLQueryItem]
    public let body: (any Encodable & Sendable)?
    public let requiresAuth: Bool
    public let requiresAttest: Bool
    /// Fixed for the lifetime of the operation so retries of the same creation reuse it.
    public let idempotencyKey: String?

    public init(
        name: String,
        method: HTTPMethod,
        path: [PathSegment],
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil,
        requiresAuth: Bool = true,
        requiresAttest: Bool = false,
        idempotent: Bool = false
    ) {
        self.name = name
        self.method = method
        self.pathSegments = path.map(\.value)
        self.queryItems = query
        self.body = body
        self.requiresAuth = requiresAuth
        self.requiresAttest = requiresAttest
        self.idempotencyKey = idempotent ? UUID().uuidString.lowercased() : nil
    }

    /// Retrying is safe for idempotent methods and for creations carrying an `Idempotency-Key`.
    public var isRetryable: Bool {
        method.isIdempotent || idempotencyKey != nil
    }
}

/// A path component: a literal from code or an identifier. There is deliberately no `String` initializer.
public struct PathSegment: Sendable, ExpressibleByStringLiteral {
    let value: String

    public init(stringLiteral value: StaticString) {
        self.value = value.description
    }

    public static func id(_ id: UUID) -> PathSegment {
        PathSegment(value: id.uuidString.lowercased())
    }

    public static func slug(_ slug: TemplateSlug) -> PathSegment {
        PathSegment(value: slug.rawValue)
    }

    private init(value: String) {
        self.value = value
    }
}

/// Template identifiers come from the server; only `[a-z0-9-]` is accepted before using one in a path.
public struct TemplateSlug: Sendable, Hashable, Codable, RawRepresentable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.wholeMatch(of: /[a-z0-9][a-z0-9-]{0,63}/) != nil else { return nil }
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let slug = TemplateSlug(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid slug"))
        }
        self = slug
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The typed HTTP client for the CasaReel API (implemented by `Networking`). The only way the app talks to the API.
public protocol APIClient: Sendable {
    func send<Response>(_ endpoint: Endpoint<Response>) async throws(AppError) -> Response
}
