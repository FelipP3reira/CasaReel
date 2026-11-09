import Domain
import Foundation
import MediaKit
import Networking
import Persistence
import SecurityKit
import UIKit
import VideoEngine

/// Composition root: the only place that knows the concrete infrastructure types.
struct AppEnvironment: Sendable {
    let configuration: AppConfiguration
    let session: SessionStore
    let tokens: TokenManager
    /// Pins for the API host, shared by the `PinningDelegate` of every API `URLSession`.
    let pinningPolicy: PinningPolicy
    let configVerifier: SignedConfigVerifier
    let apiClient: any APIClient
    let photoPreparer: any PhotoPreparing
    let photoAnalyzer: any PhotoAnalyzing
    let videoRenderer: any VideoRenderer
    let localStore: any LocalStore

    var deepLinkParser: DeepLinkParser {
        DeepLinkParser(host: configuration.universalLinkHost)
    }

    @MainActor
    static func live(infoDictionary: [String: Any]) throws(AppConfigurationError) -> AppEnvironment {
        let configuration = try AppConfiguration(infoDictionary: infoDictionary)
        purgeLeftoverPhotoFiles()
        let verifier: SignedConfigVerifier
        do {
            verifier = try SignedConfigVerifier(publicKey: configuration.configSigningPublicKey)
        } catch {
            throw .invalidValue(AppConfiguration.InfoKey.configSigningPublicKey)
        }
        let pinning = PinningPolicy(pinnedHosts: [configuration.apiBaseURL.host() ?? ""], pins: configuration.publicKeyPins)
        let integrity = IntegritySignals()
        // Collected once: the signals don't change while the process runs.
        let deviceRisk = IntegritySignals.headerValue(for: integrity.collect())
        let clientConfiguration = APIClientConfiguration(
            baseURL: configuration.apiBaseURL,
            userAgent: userAgent(infoDictionary: infoDictionary),
            deviceRisk: { deviceRisk }
        )

        // Token refresh and App Attest registration use a client without session or attestation,
        // so a 401 or an attestation can never recurse into themselves.
        let bareClient = URLSessionAPIClient(configuration: clientConfiguration, pinningPolicy: pinning, tokens: nil, attest: nil)
        let tokens = TokenManager(store: KeychainStore(), refresher: APITokenRefresher(unauthenticatedClient: bareClient))
        let attest = AppAttestClient(
            provider: DeviceAttestProvider(),
            server: APIAttestServer(client: bareClient),
            // Separate service: the attested key belongs to the device and survives sign-out/revocation.
            store: KeychainStore(service: "br.com.casareel.app.device")
        )
        let apiClient = URLSessionAPIClient(configuration: clientConfiguration, pinningPolicy: pinning, tokens: tokens, attest: attest)

        return AppEnvironment(
            configuration: configuration,
            session: SessionStore(),
            tokens: tokens,
            pinningPolicy: pinning,
            configVerifier: verifier,
            apiClient: apiClient,
            photoPreparer: PhotoPreparationService(),
            photoAnalyzer: PhotoAnalysisService(),
            videoRenderer: AVFoundationVideoRenderer(),
            localStore: SwiftDataLocalStore()
        )
    }

    /// Mirrors server-side revocations into the global session state; runs for the app's lifetime.
    @MainActor
    func observeSessionEvents() async {
        for await event in tokens.events where event == .revoked {
            session.revoke()
        }
    }

    /// Photos staged or prepared by a previous run (app killed mid-selection) are never reused: delete them.
    private static func purgeLeftoverPhotoFiles() {
        let temporary = FileManager.default.temporaryDirectory
        for folder in ["CasaReelPhotos", "CasaReelInbox"] {
            try? FileManager.default.removeItem(at: temporary.appending(path: folder, directoryHint: .isDirectory))
        }
    }

    @MainActor
    private static func userAgent(infoDictionary: [String: Any]) -> String {
        let version = infoDictionary["CFBundleShortVersionString"] as? String ?? "0"
        let build = infoDictionary["CFBundleVersion"] as? String ?? "0"
        return "CasaReel-iOS/\(version) (\(build); iOS \(UIDevice.current.systemVersion))"
    }
}
