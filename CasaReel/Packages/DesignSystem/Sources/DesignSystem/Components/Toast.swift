import Observation
import SwiftUI

public struct ToastMessage: Identifiable, Equatable, Sendable {
    public enum Style: Sendable {
        case info
        case success
        case error
    }

    public let id = UUID()
    public let text: LocalizedStringResource
    public let style: Style

    public init(_ text: LocalizedStringResource, style: Style = .info) {
        self.text = text
        self.style = style
    }

    public static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// Shows one toast at a time; a new toast replaces the current one.
@Observable
@MainActor
public final class ToastCenter {
    public private(set) var current: ToastMessage?
    private var dismissTask: Task<Void, Never>?

    public init() {}

    public func show(_ message: ToastMessage, duration: Duration = .seconds(3)) {
        current = message
        AccessibilityNotification.Announcement(String(localized: message.text)).post()
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, self?.current?.id == message.id else { return }
            self?.current = nil
        }
    }

    public func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}

struct ToastView: View {
    let message: ToastMessage
    let onDismiss: () -> Void

    private var icon: String {
        switch message.style {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        Button(action: onDismiss) {
            Label { Text(message.text) } icon: { Image(systemName: icon) }
                .font(DSFont.callout.weight(.medium))
                .foregroundStyle(DSColor.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum, alignment: .leading)
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
                .background(RoundedRectangle(cornerRadius: Radius.medium).fill(DSColor.surface))
                .dsShadow(.floating)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Toque para fechar", bundle: .module))
    }
}

extension View {
    /// Presents the toasts published by `center` at the bottom of the view.
    public func toastHost(_ center: ToastCenter) -> some View {
        modifier(ToastHostModifier(center: center))
    }
}

private struct ToastHostModifier: ViewModifier {
    let center: ToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = center.current {
                ToastView(message: message) { center.dismiss() }
                    .padding(Spacing.medium)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: center.current)
    }
}
