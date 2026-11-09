import SwiftUI

/// Covers sensitive screens with an opaque overlay whenever the scene is not active,
/// so their content never appears in the app switcher snapshot.
struct ScreenPrivacyModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.overlay {
            if scenePhase != .active {
                ZStack {
                    DSColor.background
                    Image(systemName: "lock.fill")
                        .font(.largeTitle)
                        .foregroundStyle(DSColor.accent)
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    public func screenPrivacy() -> some View {
        modifier(ScreenPrivacyModifier())
    }
}
