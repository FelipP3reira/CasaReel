import Domain
import MediaKit
import Networking
import Persistence
import SecurityKit
import VideoEngine

/// Composition root: the only place that knows the concrete infrastructure types.
struct AppEnvironment: Sendable {
    let configuration: AppConfiguration
    let secureStore: any SecureStore
    let apiClient: any APIClient
    let mediaProcessor: any MediaProcessor
    let videoRenderer: any VideoRenderer
    let localStore: any LocalStore

    static func live(infoDictionary: [String: Any]) throws(AppConfigurationError) -> AppEnvironment {
        AppEnvironment(
            configuration: try AppConfiguration(infoDictionary: infoDictionary),
            secureStore: KeychainSecureStore(),
            apiClient: URLSessionAPIClient(),
            mediaProcessor: DefaultMediaProcessor(),
            videoRenderer: AVFoundationVideoRenderer(),
            localStore: SwiftDataLocalStore()
        )
    }
}
