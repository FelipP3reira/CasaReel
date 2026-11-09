import DesignSystem
import SwiftUI

/// Sign-in placeholder until Sign in with Apple arrives in P05.
struct AuthPlaceholderView: View {
    let isRevoked: Bool
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.large) {
                if isRevoked {
                    ErrorBanner("Sua sessão foi encerrada. Entre novamente.")
                }
                EmptyState(
                    systemImage: "house.fill",
                    title: "Bem-vindo ao CasaReel",
                    message: "Transforme as fotos do seu imóvel em um vídeo de apresentação."
                )
                #if DEBUG
                // Debug-only shortcut; Release builds have no way past this screen until P05.
                PrimaryButton("Entrar (provisório)", systemImage: "arrow.right.circle", action: onContinue)
                #else
                Text("O login estará disponível em breve.")
                    .font(DSFont.callout)
                    .foregroundStyle(DSColor.textSecondary)
                #endif
            }
            .padding(Spacing.large)
        }
        .background(DSColor.background)
    }
}
