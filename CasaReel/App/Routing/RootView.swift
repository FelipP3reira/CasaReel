import DesignSystem
import SwiftUI

/// Placeholder home screen; replaced by the navigation shell in P02.
struct RootView: View {
    let environment: AppEnvironment

    var body: some View {
        VStack(spacing: Spacing.medium) {
            Image(systemName: "house.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Bem-vindo ao CasaReel")
                .font(.title2.bold())
            Text("Transforme as fotos do seu imóvel em um vídeo de apresentação.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.large)
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
