import DesignSystem
import Domain
import SwiftUI

// Placeholder screens; each one is replaced by its feature module in later prompts.

struct PropertyListScreen: View {
    let router: Router

    /// Fixed identifier so the sample detail screen can be reached before P06 adds real data.
    private static let sampleID = UUID(uuid: (0x3F, 0x25, 0x04, 0xE0, 0x4F, 0x89, 0x11, 0xD3,
                                              0x9A, 0x0C, 0x03, 0x05, 0xE8, 0x2C, 0x33, 0x01))

    var body: some View {
        PlaceholderScroll {
            EmptyState(
                systemImage: "house",
                title: "Nenhum imóvel ainda",
                message: "Cadastre seu primeiro imóvel para criar um vídeo.",
                actionTitle: "Ver imóvel de exemplo"
            ) {
                router.push(.propertyDetail(id: Self.sampleID))
            }
        }
        .navigationTitle(Text("Imóveis"))
    }
}

struct PropertyDetailScreen: View {
    let id: UUID

    var body: some View {
        PlaceholderScroll {
            Card {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    Tag("Rascunho")
                    Text("Imóvel de exemplo")
                        .font(DSFont.title)
                        .foregroundStyle(DSColor.textPrimary)
                    Text("Os detalhes do imóvel aparecerão aqui.")
                        .font(DSFont.body)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .navigationTitle(Text("Imóvel"))
        .navigationBarTitleDisplayMode(.inline)
        .screenPrivacy()
    }
}

struct SubscriptionScreen: View {
    var body: some View {
        PlaceholderScroll {
            EmptyState(
                systemImage: "star.circle",
                title: "Planos",
                message: "As opções de assinatura aparecerão aqui."
            )
        }
        .navigationTitle(Text("Assinatura"))
        .screenPrivacy()
    }
}

struct PrivacyScreen: View {
    var body: some View {
        PlaceholderScroll {
            EmptyState(
                systemImage: "hand.raised",
                title: "Privacidade",
                message: "Aqui você poderá gerenciar consentimentos, exportar e excluir seus dados."
            )
        }
        .navigationTitle(Text("Privacidade"))
        .screenPrivacy()
    }
}

struct SettingsScreen: View {
    @State private var displayName = ""

    var body: some View {
        PlaceholderScroll {
            Card {
                TextFieldRow(
                    "Nome de exibição",
                    text: $displayName,
                    prompt: "Como você quer ser chamado",
                    rules: [.required, .minLength(2)]
                )
            }
        }
        .navigationTitle(Text("Ajustes"))
        .screenPrivacy()
    }
}

/// Scrollable page background so large Dynamic Type sizes never clip content.
private struct PlaceholderScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            content.padding(Spacing.medium)
        }
        .background(DSColor.background)
    }
}
