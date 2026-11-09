import SwiftUI

/// Full-width button styles; the label wraps instead of truncating at large Dynamic Type sizes.
struct DSButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSFont.button)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .foregroundStyle(kind == .primary ? DSColor.onAccent : DSColor.accent)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium)
                    .fill(kind == .primary ? DSColor.accent : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.medium)
                    .strokeBorder(DSColor.accent, lineWidth: kind == .secondary ? 1.5 : 0)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: Radius.medium))
    }
}

public struct PrimaryButton: View {
    private let title: LocalizedStringResource
    private let systemImage: String?
    private let action: () -> Void

    public init(_ title: LocalizedStringResource, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(DSButtonStyle(kind: .primary))
    }
}

public struct SecondaryButton: View {
    private let title: LocalizedStringResource
    private let systemImage: String?
    private let action: () -> Void

    public init(_ title: LocalizedStringResource, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(DSButtonStyle(kind: .secondary))
    }
}

/// Primary button that blocks repeated taps while an operation is running.
public struct LoadingButton: View {
    private let title: LocalizedStringResource
    private let isLoading: Bool
    private let action: () -> Void

    public init(_ title: LocalizedStringResource, isLoading: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(DSColor.onAccent)
                }
            }
        }
        .buttonStyle(DSButtonStyle(kind: .primary))
        .disabled(isLoading)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isLoading ? Text("Carregando", bundle: .module) : Text(verbatim: ""))
    }
}

private struct ButtonLabel: View {
    let title: LocalizedStringResource
    let systemImage: String?

    var body: some View {
        if let systemImage {
            Label { Text(title) } icon: { Image(systemName: systemImage) }
        } else {
            Text(title)
        }
    }
}
