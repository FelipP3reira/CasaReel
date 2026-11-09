import Domain
import SwiftUI

@main
struct CasaReelApp: App {
    private let environment: Result<AppEnvironment, AppConfigurationError>

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        environment = Result { () throws(AppConfigurationError) in try AppEnvironment.live(infoDictionary: info) }
        if case .failure(let error) = environment {
            Log.bootstrap.error("Invalid app configuration: \(String(describing: error), privacy: .private)")
        }
    }

    var body: some Scene {
        WindowGroup {
            switch environment {
            case .success(let environment):
                RootView(environment: environment)
            case .failure:
                ConfigurationErrorView()
            }
        }
    }
}
