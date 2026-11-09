import Domain
import MediaKit
import Networking
import Persistence
import SecurityKit
import VideoEngine

/// Composition root: the only place that knows the concrete infrastructure types.
/// `TokenManager` and `AppAttestClient` are wired in P04, once `Networking` implements their server calls.
struct AppEnvironment: Sendable {
    let configuration: AppConfiguration
    let session: SessionStore
    let secureStore: any SecureStore
    /// Pins for the API host, shared with the `PinningDelegate` of every API `URLSession`.
    let pinningPolicy: PinningPolicy
    let configVerifier: SignedConfigVerifier
    let integritySignals: IntegritySignals
    let apiClient: any APIClient
    let mediaProcessor: any MediaProcessor
    let videoRenderer: any VideoRenderer
    let localStore: any LocalStore

    var deepLinkParser: DeepLinkParser {
        DeepLinkParser(host: configuration.universalLinkHost)
    }

    @MainActor
    static func live(infoDictionary: [String: Any]) throws(AppConfigurationError) -> AppEnvironment {
        let configuration = try AppConfiguration(infoDictionary: infoDictionary)
        let verifier: SignedConfigVerifier
        do {
            verifier = try SignedConfigVerifier(publicKey: configuration.configSigningPublicKey)
        } catch {
            throw .invalidValue(AppConfiguration.InfoKey.configSigningPublicKey)
        }
        return AppEnvironment(
            configuration: configuration,
            session: SessionStore(),
            secureStore: KeychainStore(),
            pinningPolicy: PinningPolicy(
                pinnedHosts: [configuration.apiBaseURL.host() ?? ""],
                pins: configuration.publicKeyPins
            ),
            configVerifier: verifier,
            integritySignals: IntegritySignals(),
            apiClient: URLSessionAPIClient(),
            mediaProcessor: DefaultMediaProcessor(),
            videoRenderer: AVFoundationVideoRenderer(),
            localStore: SwiftDataLocalStore()
        )
    }
}
