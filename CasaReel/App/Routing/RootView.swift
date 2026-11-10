import DesignSystem
import Domain
import FeaturePhotos
import FeatureWalk3D
import SwiftUI

/// Chooses between the sign-in flow and the tab shell, and handles incoming Universal Links.
struct RootView: View {
    let environment: AppEnvironment
    @State private var router = Router()
    @State private var toasts = ToastCenter()
    /// Lives above the tabs so the editor (P10/P11) can use the photos picked in "Criar".
    @State private var photoSelection: PhotoSelectionModel
    @State private var editor = EditorSession()
    /// Kept above the tabs so an export or render keeps going while the user looks at other screens.
    @State private var walk3D: Walk3DModel

    init(environment: AppEnvironment) {
        self.environment = environment
        _photoSelection = State(initialValue: PhotoSelectionModel(preparer: environment.photoPreparer, analyzer: environment.photoAnalyzer))
        let exporter = environment.walk3DExporter, renderer = environment.walk3DRenderer
        // Local mode: no account yet, so the free plan applies (watermark on).
        _walk3D = State(initialValue: Walk3DModel(
            watermark: true,
            export: { photos, videos in exporter.export(photos: photos, videos: videos) },
            render: { package, watermark in renderer.render(package: package, options: .init(watermark: watermark)) }
        ))
    }

    private var session: SessionStore { environment.session }

    var body: some View {
        Group {
            switch session.state {
            case .signedOut, .revoked:
                AuthPlaceholderView(isRevoked: session.state == .revoked) { session.signIn() }
            case .signedIn:
                MainTabView(router: router, photoSelection: photoSelection, editor: editor, environment: environment) {
                    router.reset()
                    photoSelection.reset()
                    editor.close()
                    walk3D.cancelExport()
                    walk3D.cancelRender()
                    Task { await environment.drafts.delete() }
                    session.signOut()
                    Task { await environment.tokens.clear() }
                }
                .environment(walk3D)
            }
        }
        .tint(DSColor.accent)
        .toastHost(toasts)
        .task { await environment.observeSessionEvents() }
        .task { await environment.purgeUnusedPhotos() }
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
