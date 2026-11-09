import Domain
import Foundation
import Testing
@testable import Networking
import SecurityKit

struct URLSessionAPIClientTests {
    private let propertyID = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301") ?? UUID()

    // MARK: Success and request shape

    @Test func decodesSuccessAndSendsStandardHeaders() async throws {
        let server = MockURLProtocol.Server([.json(propertyJSON)])
        let property = try await makeClient(server).send(API.property(propertyID))

        #expect(property.title == "Casa de praia")
        #expect(property.visibility == .private)
        let request = try #require(server.requests.first)
        #expect(request.url?.path() == "/v1/properties/3f2504e0-4f89-11d3-9a0c-0305e82c3301")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "pt-BR, en")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "CasaReel-iOS/0.1.0 (1; iOS 17.0)")
        #expect(request.value(forHTTPHeaderField: "X-Device-Risk") == "v1;simulator")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == nil)
        #expect(request.value(forHTTPHeaderField: AttestHeader.assertionName) == nil)
    }

    @Test func encodesBodyQueryAndIdempotencyKey() async throws {
        let server = MockURLProtocol.Server([.json(propertyJSON, status: 201), .json(#"{"items":[],"nextCursor":null}"#)])
        let client = makeClient(server)
        _ = try await client.send(API.createProperty(PropertyCreate(title: "Casa & Praia/1", cityPublic: "Ubatuba")))
        let page = try await client.send(API.properties(cursor: "a b&c=d", limit: 500))

        #expect(page.items.isEmpty)
        let create = server.requests[0]
        #expect(create.httpMethod == "POST")
        #expect(create.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(create.value(forHTTPHeaderField: "Idempotency-Key")?.count == 36)
        let body = try JSONSerialization.jsonObject(with: try #require(create.httpBody)) as? [String: String]
        #expect(body?["title"] == "Casa & Praia/1")

        let list = try #require(server.requests[1].url)
        let items = URLComponents(url: list, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "cursor", value: "a b&c=d")))
        #expect(items.contains(URLQueryItem(name: "limit", value: "100")))
        #expect(list.path() == "/v1/properties")
    }

    @Test func publicEndpointsSendNoAuthorization() async throws {
        let server = MockURLProtocol.Server([.json(#"{"challenge":"c1","expiresAt":"2026-11-09T12:00:00Z"}"#)])
        let challenge = try await makeClient(server, tokens: nil).send(API.attestChallenge())
        #expect(challenge.challenge == "c1")
        #expect(server.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func attestedRoutesCarryAssertionOrRiskStatus() async throws {
        let job = #"{"id":"3f2504e0-4f89-11d3-9a0c-0305e82c3301","type":"render_video","status":"queued","progress":0,"etaSeconds":null,"errorCode":null,"queuedAt":"2026-11-09T12:00:00Z","finishedAt":null}"#
        let server = MockURLProtocol.Server([.json(job, status: 201), .json(job, status: 201)])
        let endpoint = API.createJob(propertyId: propertyID, JobCreate(type: .renderVideo))

        _ = try await makeClient(server).send(endpoint)
        _ = try await makeClient(server, attest: nil).send(endpoint)

        #expect(server.requests[0].value(forHTTPHeaderField: AttestHeader.assertionName)?.hasPrefix("assertion-") == true)
        #expect(server.requests[1].value(forHTTPHeaderField: AttestHeader.statusName) == "unsupported")
    }

    @Test func emptyResponsesIgnoreBodyAndContentType() async throws {
        let server = MockURLProtocol.Server([MockURLProtocol.Reply(status: 204, headers: [:])])
        #expect(try await makeClient(server).send(API.deleteProperty(propertyID)) == EmptyResponse())
    }

    // MARK: 401 and refresh

    @Test func unauthorizedTriggersOneRefreshAndRetriesWithNewToken() async throws {
        let tokens = MockTokens()
        let server = MockURLProtocol.Server([.problem(status: 401), .json(propertyJSON)])

        _ = try await makeClient(server, tokens: tokens).send(API.property(propertyID))

        #expect(await tokens.refreshes == 1)
        #expect(server.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer token-1", "Bearer token-2"])
    }

    @Test func failedRefreshReportsRevokedSession() async {
        let tokens = MockTokens(refreshOutcome: .sessionRevoked)
        let server = MockURLProtocol.Server([.problem(status: 401, code: "session_revoked")])

        await #expect(throws: AppError(.sessionRevoked)) { try await makeClient(server, tokens: tokens).send(API.me()) }
        #expect(server.requests.count == 1)
    }

    @Test func repeatedUnauthorizedDoesNotLoop() async throws {
        let tokens = MockTokens()
        let server = MockURLProtocol.Server([.problem(status: 401), .problem(status: 401)])

        let error = await #expect(throws: AppError.self) { try await makeClient(server, tokens: tokens).send(API.me()) }
        #expect(error?.code == .unauthorized)
        #expect(await tokens.refreshes == 1)
        #expect(server.requests.count == 2)
    }

    // MARK: Retries

    @Test func rateLimitHonorsRetryAfter() async throws {
        let sleeper = SleepRecorder()
        let server = MockURLProtocol.Server([.problem(status: 429, code: "rate_limited", headers: ["Retry-After": "7"]), .json(propertyJSON)])

        _ = try await makeClient(server, sleeper: sleeper).send(API.property(propertyID))
        #expect(sleeper.recorded == [.seconds(7)])
    }

    @Test func serverErrorsRetryWithExponentialBackoffThenFail() async {
        let sleeper = SleepRecorder()
        let server = MockURLProtocol.Server([.problem(status: 503), .problem(status: 502), .problem(status: 500)])

        let error = await #expect(throws: AppError.self) { try await makeClient(server, sleeper: sleeper).send(API.me()) }
        #expect(error?.code == .server)
        #expect(server.requests.count == 3)
        #expect(sleeper.recorded == [.milliseconds(500), .seconds(1)])
    }

    @Test func retriedCreationReusesItsIdempotencyKey() async throws {
        let server = MockURLProtocol.Server([.problem(status: 503), MockURLProtocol.Reply(error: URLError(.networkConnectionLost)), .json(propertyJSON, status: 201)])

        _ = try await makeClient(server).send(API.createProperty(PropertyCreate(title: "Casa")))

        let keys = server.requests.compactMap { $0.value(forHTTPHeaderField: "Idempotency-Key") }
        #expect(keys.count == 3)
        #expect(Set(keys).count == 1)
    }

    @Test func nonIdempotentRequestIsNotRetried() async {
        let server = MockURLProtocol.Server([.problem(status: 503), .json(propertyJSON)])
        await #expect(throws: AppError.self) {
            try await makeClient(server).send(API.updateProperty(propertyID, PropertyUpdate(title: "Novo")))
        }
        #expect(server.requests.count == 1)
    }

    @Test func clientErrorsAreNotRetried() async {
        let server = MockURLProtocol.Server([.problem(status: 404), .json(propertyJSON)])
        await #expect(throws: AppError.self) { try await makeClient(server).send(API.property(propertyID)) }
        #expect(server.requests.count == 1)
    }

    // MARK: Errors and limits

    @Test func mapsProblemJSONWithStableCode() async {
        let server = MockURLProtocol.Server([.problem(status: 402, code: "payment_required")])
        let error = await #expect(throws: AppError.self) { try await makeClient(server).send(API.entitlements()) }
        #expect(error?.code == .paymentRequired)
        #expect(error?.status == 402)
        #expect(error?.problemCode == "payment_required")
    }

    @Test func keepsUnknownProblemCodesAndFieldErrors() async {
        let body = #"{"type":"about:blank","title":"Inválido","status":422,"code":"title_taken","errors":{"title":["já existe"]}}"#
        let server = MockURLProtocol.Server([MockURLProtocol.Reply(status: 422, headers: ["Content-Type": "application/problem+json; charset=utf-8"], body: Data(body.utf8))])
        let error = await #expect(throws: AppError.self) {
            try await makeClient(server).send(API.createProperty(PropertyCreate(title: "Casa")))
        }
        #expect(error?.code == .validation)
        #expect(error?.problemCode == "title_taken")
        #expect(error?.fieldErrors == ["title": ["já existe"]])
    }

    @Test func rejectsOversizedResponses() async {
        let huge = MockURLProtocol.Reply(body: Data(repeating: 0x20, count: 4096))
        let server = MockURLProtocol.Server([huge])
        let error = await #expect(throws: AppError.self) { try await makeClient(server, maxResponseBytes: 1024).send(API.me()) }
        #expect(error?.code == .responseTooLarge)
    }

    @Test func rejectsUnexpectedContentType() async {
        let html = MockURLProtocol.Reply(headers: ["Content-Type": "text/html"], body: Data("<html>".utf8))
        let server = MockURLProtocol.Server([html])
        let error = await #expect(throws: AppError.self) { try await makeClient(server).send(API.me()) }
        #expect(error?.code == .unexpectedContentType)
    }

    @Test func rejectsBodyMissingRequiredFields() async {
        let server = MockURLProtocol.Server([.json(#"{"id":"3f2504e0-4f89-11d3-9a0c-0305e82c3301","title":"Casa"}"#)])
        let error = await #expect(throws: AppError.self) { try await makeClient(server).send(API.property(propertyID)) }
        #expect(error?.code == .invalidResponse)
    }

    @Test func toleratesUnknownEnumValues() async throws {
        let json = propertyJSON.replacingOccurrences(of: #""private""#, with: #""friends_only""#)
        let server = MockURLProtocol.Server([.json(json)])
        #expect(try await makeClient(server).send(API.property(propertyID)).visibility == .unknown)
    }

    @Test(arguments: [
        (URLError.Code.timedOut, AppError.Code.timeout),
        (.notConnectedToInternet, .offline),
        (.cancelled, .cancelled),
        (.serverCertificateUntrusted, .unknown),
    ])
    func mapsTransportErrors(code: URLError.Code, expected: AppError.Code) {
        #expect(URLSessionAPIClient.map(URLError(code)).code == expected)
    }

    @Test func offlineGetIsRetried() async throws {
        let server = MockURLProtocol.Server([MockURLProtocol.Reply(error: URLError(.notConnectedToInternet)), .json(propertyJSON)])
        _ = try await makeClient(server).send(API.property(propertyID))
        #expect(server.requests.count == 2)
    }
}

struct NetworkingHelpersTests {
    @Test func retryAfterParsesSecondsAndHTTPDates() throws {
        let url = try #require(URL(string: "https://x.example"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func response(_ value: String) -> HTTPURLResponse? {
            HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": value])
        }
        #expect(URLSessionAPIClient.retryAfter(from: try #require(response("12")), now: now) == .seconds(12))
        let date = try #require(response("Fri, 15 Jan 2027 08:00:30 GMT"))
        #expect(URLSessionAPIClient.retryAfter(from: date, now: now) == .seconds(30))
        #expect(URLSessionAPIClient.retryAfter(from: try #require(response("soon")), now: now) == nil)
    }

    @Test func retryPolicyCapsDelays() {
        let policy = RetryPolicy(maxDelay: .seconds(2), maxRetryAfter: .seconds(10), random: { 1 })
        #expect(policy.delay(afterAttempt: 1, retryAfter: nil) == .milliseconds(500))
        #expect(policy.delay(afterAttempt: 5, retryAfter: nil) == .seconds(2))
        #expect(policy.delay(afterAttempt: 1, retryAfter: .seconds(300)) == .seconds(10))
    }

    @Test(arguments: [
        ("application/json", true), ("application/json; charset=utf-8", true),
        ("application/problem+json", true), ("text/html", false), ("", false),
    ])
    func detectsJSONContentTypes(contentType: String, expected: Bool) {
        #expect(URLSessionAPIClient.isJSON(contentType) == expected)
    }

    @Test func mapsTokenErrors() {
        #expect(URLSessionAPIClient.map(TokenError.notAuthenticated).code == .unauthorized)
        #expect(URLSessionAPIClient.map(TokenError.sessionRevoked).code == .sessionRevoked)
        #expect(URLSessionAPIClient.map(TokenError.refreshFailed).code == .offline)
        #expect(URLSessionAPIClient.map(TokenError.storageFailed).code == .unknown)
    }

    @Test func templateSlugRejectsPathTricks() {
        #expect(TemplateSlug(rawValue: "classico-praia") != nil)
        #expect(TemplateSlug(rawValue: "../me") == nil)
        #expect(TemplateSlug(rawValue: "a/b") == nil)
        #expect(TemplateSlug(rawValue: "") == nil)
    }
}

struct AuthAdapterTests {
    @Test func refresherReturnsNewPair() async throws {
        let server = MockURLProtocol.Server([.json(#"{"accessToken":"a2","refreshToken":"r2","expiresIn":900}"#)])
        let refresher = APITokenRefresher(unauthenticatedClient: makeClient(server, tokens: nil))
        let pair = try await refresher.refresh(using: "r1")

        #expect(pair == TokenPair(accessToken: "a2", refreshToken: "r2", expiresIn: 900))
        let body = try JSONSerialization.jsonObject(with: try #require(server.requests.first?.httpBody)) as? [String: String]
        #expect(body == ["refreshToken": "r1"])
        #expect(server.requests.first?.url?.path() == "/v1/auth/refresh")
    }

    @Test(arguments: [401, 403])
    func refresherTreatsRejectionAsRevoked(status: Int) async {
        let server = MockURLProtocol.Server([.problem(status: status, code: status == 401 ? "session_revoked" : nil)])
        let refresher = APITokenRefresher(unauthenticatedClient: makeClient(server, tokens: nil))
        await #expect(throws: TokenRefreshError.sessionRevoked) { try await refresher.refresh(using: "r1") }
    }

    @Test func refresherTreatsServerErrorsAsTransient() async {
        let server = MockURLProtocol.Server([.problem(status: 500), .problem(status: 500), .problem(status: 500)])
        let refresher = APITokenRefresher(unauthenticatedClient: makeClient(server, tokens: nil))
        await #expect(throws: TokenRefreshError.transient) { try await refresher.refresh(using: "r1") }
    }

    @Test func attestServerCallsChallengeAndRegister() async throws {
        let server = MockURLProtocol.Server([
            .json(#"{"challenge":"c9","expiresAt":"2026-11-09T12:00:00Z"}"#),
            MockURLProtocol.Reply(status: 204, headers: [:]),
        ])
        let attestServer = APIAttestServer(client: makeClient(server, tokens: nil, attest: nil))

        #expect(try await attestServer.challenge() == "c9")
        try await attestServer.register(keyId: "k1", attestationObject: Data([1, 2]), challenge: "c9")

        #expect(server.requests.map { $0.url?.path() } == ["/v1/attest/challenge", "/v1/attest/register"])
        let body = try JSONSerialization.jsonObject(with: try #require(server.requests[1].httpBody)) as? [String: String]
        #expect(body == ["keyId": "k1", "attestationObject": "AQI=", "challenge": "c9"])
    }

    @Test func tokenManagerAndClientRefreshEndToEnd() async throws {
        let api = MockURLProtocol.Server([.problem(status: 401), .json(propertyJSON)])
        let auth = MockURLProtocol.Server([.json(#"{"accessToken":"fresh","refreshToken":"r2","expiresIn":900}"#)])
        let tokens = TokenManager(store: InMemoryStore(), refresher: APITokenRefresher(unauthenticatedClient: makeClient(auth, tokens: nil)))
        try await tokens.store(TokenPair(accessToken: "stale", refreshToken: "r1", expiresIn: 900))

        _ = try await makeClient(api, tokens: tokens).send(API.property(UUID()))

        #expect(api.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer stale", "Bearer fresh"])
    }
}

/// Minimal in-memory secure store for the end-to-end token test.
final class InMemoryStore: SecureStore, @unchecked Sendable {
    private var items: [String: Data] = [:]
    private let lock = NSLock()

    func set(_ data: Data, for key: String, protection: SecureStoreProtection) throws(SecureStoreError) {
        lock.withLock { items[key] = data }
    }

    func data(for key: String) throws(SecureStoreError) -> Data? {
        lock.withLock { items[key] }
    }

    func delete(_ key: String) throws(SecureStoreError) {
        lock.withLock { _ = items.removeValue(forKey: key) }
    }

    func deleteAll() throws(SecureStoreError) {
        lock.withLock { items.removeAll() }
    }
}
