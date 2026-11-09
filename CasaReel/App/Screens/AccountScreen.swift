import DesignSystem
import Domain
import SwiftUI

struct AccountScreen: View {
    let router: Router
    let onSignOut: () -> Void

    var body: some View {
        List {
            Section {
                row("Assinatura", systemImage: "star", route: .subscription)
                row("Privacidade", systemImage: "hand.raised", route: .privacy)
                row("Ajustes", systemImage: "gearshape", route: .settings)
            }
            Section {
                Button(role: .destructive, action: onSignOut) {
                    Label("Sair", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(minHeight: TouchTarget.minimum)
                }
            }
        }
        .navigationTitle(Text("Conta"))
        .screenPrivacy()
    }

    private func row(_ title: LocalizedStringResource, systemImage: String, route: AppRoute) -> some View {
        Button {
            router.push(route)
        } label: {
            Label { Text(title) } icon: { Image(systemName: systemImage) }
                .foregroundStyle(DSColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum, alignment: .leading)
                .contentShape(Rectangle())
        }
        .accessibilityAddTraits(.isLink)
    }
}
