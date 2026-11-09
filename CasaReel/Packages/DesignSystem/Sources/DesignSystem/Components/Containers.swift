import SwiftUI

public struct Card<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.medium).fill(DSColor.surface))
            .dsShadow(.card)
            .accessibilityElement(children: .contain)
    }
}

public struct EmptyState: View {
    private let systemImage: String
    private let title: LocalizedStringResource
    private let message: LocalizedStringResource
    private let actionTitle: LocalizedStringResource?
    private let action: (() -> Void)?

    public init(
        systemImage: String,
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        actionTitle: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Spacing.medium) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(DSColor.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(DSFont.title)
                .foregroundStyle(DSColor.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                PrimaryButton(actionTitle, action: action)
                    .padding(.top, Spacing.small)
            }
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity)
    }
}

public struct Tag: View {
    public enum Style: Sendable {
        case neutral
        case success
        case warning
        case danger

        var color: Color {
            switch self {
            case .neutral: DSColor.textSecondary
            case .success: DSColor.success
            case .warning: DSColor.warning
            case .danger: DSColor.danger
            }
        }
    }

    private let title: LocalizedStringResource
    private let style: Style

    public init(_ title: LocalizedStringResource, style: Style = .neutral) {
        self.title = title
        self.style = style
    }

    public var body: some View {
        Text(title)
            .font(DSFont.caption.weight(.semibold))
            .foregroundStyle(style.color)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.xSmall)
            .background(Capsule().strokeBorder(style.color, lineWidth: 1))
    }
}
