import Domain
import Foundation
import os
@testable import Networking
import SecurityKit

/// Scripted HTTP server: each test registers a unique host and the responses to serve in order.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int = 200
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body = Data()
        var error: URLError?

        static func json(_ json: String, status: Int = 200, headers: [String: String] = [:]) -> Reply {
            Reply(status: status, headers: ["Content-Type": "application/json"].merging(headers) { $1 }, body: Data(json.utf8))
        }

        static func problem(status: Int, code: String? = nil, headers: [String: String] = [:]) -> Reply {
            let codeField = code.map { #","code":"\#($0)""# } ?? ""
            let body = #"{"type":"about:blank","title":"Erro","status":\#(status)\#(codeField)}"#
            return Reply(status: status, headers: ["Content-Type": "application/problem+json"].merging(headers) { $1 }, body: Data(body.utf8))
        }
    }

    final class Server: Sendable {
        let host = "test-\(UUID().uuidString.lowercased()).casareel.example"
        private let state: OSAllocatedUnfairLock<(replies: [Reply], requests: [URLRequest])>

        init(_ replies: [Reply]) {
            state = OSAllocatedUnfairLock(initialState: (replies, []))
            MockURLProtocol.servers.withLock { $0[host] = self }
        }

        var requests: [URLRequest] { state.withLock { $0.requests } }

        fileprivate func next(for request: URLRequest) -> Reply {
            state.withLock { state in
                state.requests.append(request)
                return state.replies.isEmpty ? .problem(status: 599) : state.replies.removeFirst()
            }
        }

        var baseURL: URL {
            URL(string: "https://\(host)/v1")!  // swiftlint:disable:this force_unwrapping
        }
    }

    static let servers = OSAllocatedUnfairLock(initialState: [String: Server]())

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host(), let server = Self.servers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        var recorded = request
        recorded.httpBody = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let reply = server.next(for: recorded)
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Token provider double: counts refreshes and can simulate a revoked session.
actor MockTokens: AccessTokenProviding {
    private(set) var token = "token-1"
    private(set) var refreshes = 0
    private let refreshOutcome: TokenError?

    init(refreshOutcome: TokenError? = nil) {
        self.refreshOutcome = refreshOutcome
    }

    func validAccessToken() async throws(TokenError) -> String { token }

    func refreshAfterRejection(of token: String) async throws(TokenError) -> String {
        refreshes += 1
        if let refreshOutcome { throw refreshOutcome }
        self.token = "token-\(refreshes + 1)"
        return self.token
    }

    func store(_ pair: TokenPair) async throws(TokenError) {}
    func clear() async {}
}

struct MockAttest: RequestAttesting {
    func header(forBody body: Data) async -> AttestHeader {
        AttestHeader(name: AttestHeader.assertionName, value: "assertion-\(body.count)")
    }
}

/// Records requested back-off delays instead of sleeping.
final class SleepRecorder: Sendable {
    private let delays = OSAllocatedUnfairLock(initialState: [Duration]())
    var recorded: [Duration] { delays.withLock { $0 } }

    func sleep(_ duration: Duration) async throws {
        delays.withLock { $0.append(duration) }
    }
}

func makeClient(
    _ server: MockURLProtocol.Server,
    tokens: (any AccessTokenProviding)? = MockTokens(),
    attest: (any RequestAttesting)? = MockAttest(),
    sleeper: SleepRecorder = SleepRecorder(),
    maxResponseBytes: Int = 1024 * 1024
) -> URLSessionAPIClient {
    let sessionConfiguration = URLSessionConfiguration.casaReelAPI
    sessionConfiguration.protocolClasses = [MockURLProtocol.self]
    sessionConfiguration.waitsForConnectivity = false
    let configuration = APIClientConfiguration(
        baseURL: server.baseURL,
        userAgent: "CasaReel-iOS/0.1.0 (1; iOS 17.0)",
        acceptLanguage: { "pt-BR, en" },
        deviceRisk: { "v1;simulator" },
        maxResponseBytes: maxResponseBytes,
        retry: RetryPolicy(random: { 1 })
    )
    return URLSessionAPIClient(
        configuration: configuration,
        sessionConfiguration: sessionConfiguration,
        pinningPolicy: nil,
        tokens: tokens,
        attest: attest,
        sleep: { try await sleeper.sleep($0) }
    )
}

let propertyJSON = #"""
{"id":"3f2504e0-4f89-11d3-9a0c-0305e82c3301","title":"Casa de praia","cityPublic":"Ubatuba",
 "visibility":"private","createdAt":"2026-11-09T12:00:00.123456Z","futureField":{"x":1}}
"""#
