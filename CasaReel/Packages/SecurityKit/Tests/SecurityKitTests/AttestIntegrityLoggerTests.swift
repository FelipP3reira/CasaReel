import CryptoKit
import Domain
import Foundation
import Testing
@testable import SecurityKit

struct AppAttestClientTests {
    private let store = InMemorySecureStore()
    private let server = MockAttestServer()

    @Test func unsupportedDeviceSendsRiskHeader() async {
        let client = AppAttestClient(provider: MockAttestProvider(isSupported: false), server: server, store: store)
        let header = await client.header(forBody: Data())
        #expect(header == AttestHeader(name: AttestHeader.statusName, value: "unsupported"))
    }

    @Test func registersOnceAndSignsBodyWithChallenge() async throws {
        let provider = MockAttestProvider()
        let client = AppAttestClient(provider: provider, server: server, store: store)
        let body = Data(#"{"title":"Casa"}"#.utf8)

        let first = await client.header(forBody: body)
        let second = await client.header(forBody: body)

        #expect(first.name == AttestHeader.assertionName)
        #expect(second.name == AttestHeader.assertionName)
        #expect(await server.registeredKeys == ["key-1"])
        #expect(try store.data(for: AppAttestClient.keyIdStorageKey) == Data("key-1".utf8))
        // Challenges: 1 for registration, then one per assertion.
        #expect(provider.lastClientDataHash == AppAttestClient.clientDataHash(body: body, challenge: "challenge-3"))
    }

    @Test func concurrentFirstRequestsRegisterASingleKey() async {
        let provider = MockAttestProvider()
        let client = AppAttestClient(provider: provider, server: server, store: store)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { _ = await client.header(forBody: Data()) }
            }
        }
        #expect(provider.generatedKeys == 1)
    }

    @Test func invalidKeyTriggersFreshAttestation() async {
        let provider = MockAttestProvider(invalidKeyOnce: true)
        try? store.set(Data("stale".utf8), for: AppAttestClient.keyIdStorageKey)
        let client = AppAttestClient(provider: provider, server: server, store: store)

        let header = await client.header(forBody: Data())
        #expect(header.name == AttestHeader.assertionName)
        #expect(await server.registeredKeys == ["key-1"])
    }

    @Test func failureDegradesToRiskHeader() async {
        let client = AppAttestClient(provider: MockAttestProvider(failAssertions: true), server: server, store: store)
        let header = await client.header(forBody: Data())
        #expect(header == AttestHeader(name: AttestHeader.statusName, value: "failed"))
    }

    @Test func clientDataHashCoversBodyAndChallenge() {
        let expected = Data(SHA256.hash(data: Data("bodychallenge".utf8)))
        #expect(AppAttestClient.clientDataHash(body: Data("body".utf8), challenge: "challenge") == expected)
    }
}

struct IntegritySignalsTests {
    private func environment(
        simulator: Bool = false,
        files: Set<String> = [],
        writable: Bool = false,
        images: [String] = ["/usr/lib/libSystem.B.dylib"],
        debugger: Bool = false
    ) -> IntegritySignals.Environment {
        IntegritySignals.Environment(
            isSimulator: simulator,
            fileExists: { files.contains($0) },
            canWriteOutsideSandbox: { writable },
            loadedImageNames: { images },
            isDebuggerAttached: { debugger }
        )
    }

    @Test func cleanDeviceHasNoSignals() {
        #expect(IntegritySignals(environment: environment()).collect().isEmpty)
    }

    @Test func compromisedDeviceReportsEverySignal() {
        let signals = IntegritySignals(environment: environment(
            files: ["/var/jb"],
            writable: true,
            images: ["/usr/lib/FridaGadget.dylib"],
            debugger: true
        )).collect()
        #expect(signals == [.debugger, .injectedLibraries, .jailbreakFiles, .sandboxEscape].sorted())
    }

    @Test func simulatorSkipsFilesystemChecks() {
        let signals = IntegritySignals(environment: environment(simulator: true, files: ["/bin/bash"], writable: true)).collect()
        #expect(signals == [.simulator])
    }

    @Test func liveCollectionRunsOnSimulator() {
        #expect(IntegritySignals().collect().contains(.simulator))
    }

    @Test func headerValueIsCompactAndStable() {
        #expect(IntegritySignals.headerValue(for: []) == "v1;none")
        #expect(IntegritySignals.headerValue(for: [.simulator, .debugger]) == "v1;debugger,simulator")
    }
}

struct SecureLoggerTests {
    @Test(arguments: [
        ("Authorization: Bearer abc.DEF-123_xyz", "Authorization: <redacted>"),
        ("token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig-nature", "token <redacted>"),
        ("contato: ana.silva+casa@exemplo.com.br", "contato: <redacted>"),
        (#"{"refresh_token": "r-123", "ok": true}"#, #"{"refresh_token": "<redacted>", "ok": true}"#),
        ("password=hunter2&user=1", "password=<redacted>&user=1"),
        ("Upload concluído em 3 s", "Upload concluído em 3 s"),
    ])
    func redactsSecrets(input: String, expected: String) {
        #expect(SecureLogger.redact(input) == expected)
    }

    @Test func redactedOutputNeverContainsTheSecret() {
        let secret = "s3cr3t-T0ken"
        let output = SecureLogger.redact("Bearer \(secret) sent to ana@exemplo.com")
        #expect(!output.contains(secret))
        #expect(!output.contains("ana@exemplo.com"))
    }

    @Test func loggingMethodsAcceptMessages() {
        let logger = SecureLogger(category: "tests")
        logger.debug("debug Bearer x")
        logger.info("info")
        logger.notice("notice")
        logger.error("error ana@exemplo.com")
    }
}

/// On the Simulator App Attest is unsupported, so the production provider must fail cleanly (never crash).
struct DeviceAttestProviderTests {
    private let provider = DeviceAttestProvider()

    @Test func isUnsupportedOnSimulator() {
        #expect(!provider.isSupported)
    }

    @Test func operationsFailWithMappedError() async {
        await #expect(throws: AttestProviderError.failed) { try await provider.generateKey() }
        await #expect(throws: AttestProviderError.failed) { try await provider.attestKey("k", clientDataHash: Data()) }
        await #expect(throws: AttestProviderError.failed) { try await provider.generateAssertion("k", clientDataHash: Data()) }
    }

    @Test func clientFallsBackToRiskHeaderWithRealProvider() async {
        let client = AppAttestClient(provider: provider, server: MockAttestServer(), store: InMemorySecureStore())
        #expect(await client.header(forBody: Data()).value == "unsupported")
    }
}
