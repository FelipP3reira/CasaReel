import DesignSystem
import Domain
import SwiftUI

/// Chooses between the sign-in flow and the tab shell, and handles incoming Universal Links.
struct RootView: View {
    let environment: AppEnvironment
    @State private var router = Router()
    @State private var toasts = ToastCenter()

    private var session: SessionStore { environment.session }

    var body: some View {
        Group {
            switch session.state {
            case .signedOut, .revoked:
                AuthPlaceholderView(isRevoked: session.state == .revoked) { session.signIn() }
            case .signedIn:
                MainTabView(router: router) {
                    router.reset()
                    session.signOut()
                }
            }
        }
        .tint(DSColor.accent)
        .toastHost(toasts)
        .onOpenURL(perform: open)
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { open(url) }
        }
    }

    private func open(_ url: URL) {
        let outcome = router.open(url, parser: environment.deepLinkParser, session: session.state)
        switch outcome {
        case .opened:
            Log.navigation.info("Deep link opened")
        case .rejectedInvalid, .rejectedSensitive, .rejectedNoSession:
            Log.navigation.notice("Deep link rejected: \(String(describing: outcome), privacy: .public)")
            toasts.show(ToastMessage("Não foi possível abrir este link.", style: .error))
        }
    }
}

/// Shown instead of crashing when the bundled configuration is invalid.
struct ConfigurationErrorView: View {
    var body: some View {
        ContentUnavailableView(
            "Não foi possível iniciar o app",
            systemImage: "exclamationmark.triangle",
            description: Text("Reinstale o aplicativo ou tente novamente mais tarde.")
        )
    }
}
