import Domain
import Foundation
import SecurityKit

/// Produces the App Attest header for a request body (`AppAttestClient` in production).
public protocol RequestAttesting: Sendable {
    func header(forBody body: Data) async -> AttestHeader
}

extension AppAttestClient: RequestAttesting {}

/// The only component that talks to the CasaReel API. Never logs bodies or sensitive headers.
public final class URLSessionAPIClient: APIClient {
    private let configuration: APIClientConfiguration
    private let session: URLSession
    private let tokens: (any AccessTokenProviding)?
    private let attest: (any RequestAttesting)?
    private let sleep: @Sendable (Duration) async throws -> Void
    private let logger = SecureLogger(category: "api")

    /// - Parameters:
    ///   - pinningPolicy: installs `PinningDelegate`; only `nil` in tests that use `URLProtocol` mocks.
    ///   - tokens: `nil` for the unauthenticated client used by token refresh and App Attest registration.
    public init(
        configuration: APIClientConfiguration,
        sessionConfiguration: URLSessionConfiguration = .casaReelAPI,
        pinningPolicy: PinningPolicy?,
        tokens: (any AccessTokenProviding)?,
        attest: (any RequestAttesting)?,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.configuration = configuration
        self.session = URLSession(
            configuration: sessionConfiguration,
            delegate: pinningPolicy.map(PinningDelegate.init(policy:)),
            delegateQueue: nil
        )
        self.tokens = tokens
        self.attest = attest
        self.sleep = sleep
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    public func send<Response>(_ endpoint: Endpoint<Response>) async throws(AppError) -> Response {
        let body = try encodeBody(of: endpoint)
        var attempt = 1
        var didRefresh = false
        while true {
            let token = endpoint.requiresAuth ? try await accessToken() : nil
            let request = try await makeRequest(for: endpoint, body: body, token: token)
            do {
                return try await perform(request, for: endpoint)
            } catch {
                if let token, !didRefresh, [.unauthorized, .sessionRevoked].contains(error.code) {
                    // One refresh per call; TokenManager reports `session_revoked` from the refresh itself.
                    didRefresh = true
                    try await refresh(after: token)
                    continue
                }
                guard error.isTransient, endpoint.isRetryable, attempt < configuration.retry.maxAttempts else {
                    logger.notice("\(endpoint.name) failed: \(error.code.rawValue) status=\(error.status.map(String.init) ?? "-")")
                    throw error
                }
                do {
                    try await sleep(configuration.retry.delay(afterAttempt: attempt, retryAfter: error.retryAfter))
                } catch {
                    throw AppError(.cancelled)
                }
                attempt += 1
            }
        }
    }

    // MARK: - Request

    private func encodeBody<Response>(of endpoint: Endpoint<Response>) throws(AppError) -> Data? {
        guard let body = endpoint.body else { return nil }
        do {
            return try JSONCoding.encoder.encode(body)
        } catch {
            throw AppError(.invalidResponse)
        }
    }

    func url<Response>(for endpoint: Endpoint<Response>) throws(AppError) -> URL {
        let path = endpoint.pathSegments.reduce(configuration.baseURL) { $0.appending(path: $1) }
        guard var components = URLComponents(url: path, resolvingAgainstBaseURL: false) else {
            throw AppError(.invalidResponse)
        }
        if !endpoint.queryItems.isEmpty { components.queryItems = endpoint.queryItems }
        guard let url = components.url else { throw AppError(.invalidResponse) }
        return url
    }

    private func makeRequest<Response>(
        for endpoint: Endpoint<Response>,
        body: Data?,
        token: String?
    ) async throws(AppError) -> URLRequest {
        var request = URLRequest(url: try url(for: endpoint))
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue(configuration.acceptLanguage(), forHTTPHeaderField: "Accept-Language")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(configuration.deviceRisk(), forHTTPHeaderField: "X-Device-Risk")
        if let key = endpoint.idempotencyKey { request.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if endpoint.requiresAttest {
            // Assertions use single-use challenges, so a retry gets a fresh one.
            let header = await attest?.header(forBody: body ?? Data())
                ?? AttestHeader(name: AttestHeader.statusName, value: "unsupported")
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        return request
    }

    // MARK: - Tokens

    private func accessToken() async throws(AppError) -> String {
        guard let tokens else { throw AppError(.unauthorized) }
        do {
            return try await tokens.validAccessToken()
        } catch {
            throw Self.map(error)
        }
    }

    private func refresh(after token: String) async throws(AppError) {
        guard let tokens else { throw AppError(.unauthorized) }
        do {
            _ = try await tokens.refreshAfterRejection(of: token)
        } catch {
            throw Self.map(error)
        }
    }

    static func map(_ error: TokenError) -> AppError {
        switch error {
        case .notAuthenticated: AppError(.unauthorized)
        case .sessionRevoked: AppError(.sessionRevoked)
        case .refreshFailed: AppError(.offline)
        case .storageFailed: AppError(.unknown)
        }
    }

    // MARK: - Response

    private func perform<Response>(_ request: URLRequest, for endpoint: Endpoint<Response>) async throws(AppError) -> Response {
        let (data, response) = try await download(request)
        let contentType = (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()

        guard (200..<300).contains(response.statusCode) else {
            let problem = Self.isJSON(contentType) ? try? JSONCoding.decoder.decode(Problem.self, from: data) : nil
            throw AppError(status: response.statusCode, problem: problem, retryAfter: Self.retryAfter(from: response))
        }
        if Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response {
            return empty
        }
        guard Self.isJSON(contentType) else { throw AppError(.unexpectedContentType, status: response.statusCode) }
        do {
            return try JSONCoding.decoder.decode(Response.self, from: data)
        } catch {
            logger.error("\(endpoint.name): response did not match the contract")
            throw AppError(.invalidResponse, status: response.statusCode)
        }
    }

    /// Streams the body and aborts as soon as it exceeds `maxResponseBytes`.
    private func download(_ request: URLRequest) async throws(AppError) -> (Data, HTTPURLResponse) {
        let limit = configuration.maxResponseBytes
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw AppError(.invalidResponse) }
            if http.expectedContentLength > Int64(limit) {
                bytes.task.cancel()
                throw AppError(.responseTooLarge, status: http.statusCode)
            }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > limit {
                    bytes.task.cancel()
                    throw AppError(.responseTooLarge, status: http.statusCode)
                }
            }
            return (data, http)
        } catch let error as AppError {
            throw error
        } catch let error as URLError {
            throw Self.map(error)
        } catch {
            throw AppError(.unknown)
        }
    }

    static func map(_ error: URLError) -> AppError {
        switch error.code {
        case .timedOut: AppError(.timeout)
        case .cancelled: AppError(.cancelled)
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
             .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
            AppError(.offline)
        default:
            // TLS and pinning failures (serverCertificate*, secureConnectionFailed) land here: never retried.
            AppError(.unknown)
        }
    }

    static func isJSON(_ contentType: String) -> Bool {
        let mediaType = contentType.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return mediaType == "application/json" || (mediaType.hasPrefix("application/") && mediaType.hasSuffix("+json"))
    }

    /// `Retry-After` as delta-seconds or an HTTP date.
    static func retryAfter(from response: HTTPURLResponse, now: Date = Date()) -> Duration? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        if let seconds = Int(value), seconds >= 0 { return .seconds(seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return .seconds(max(0, date.timeIntervalSince(now).rounded(.up)))
    }
}
