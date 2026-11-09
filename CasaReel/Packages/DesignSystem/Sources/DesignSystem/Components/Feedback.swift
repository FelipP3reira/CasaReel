import SwiftUI

/// Inline error with optional retry; stacks vertically when the text gets large.
public struct ErrorBanner: View {
    private let message: LocalizedStringResource
    private let retry: (() -> Void)?

    public init(_ message: LocalizedStringResource, retry: (() -> Void)? = nil) {
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.small) { content }
            VStack(alignment: .leading, spacing: Spacing.small) { content }
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.medium).fill(DSColor.danger.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(DSColor.danger, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var content: some View {
        Label { Text(message) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
            .font(DSFont.callout)
            .foregroundStyle(DSColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
        if let retry {
            Button(action: retry) {
                Text("Tentar novamente", bundle: .module)
                    .font(DSFont.callout.weight(.semibold))
                    .frame(minHeight: TouchTarget.minimum)
            }
            .foregroundStyle(DSColor.danger)
        }
    }
}

public struct ProgressRing: View {
    private let progress: Double
    private let lineWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(progress: Double, lineWidth: CGFloat = 6) {
        self.progress = Self.clamped(progress)
        self.lineWidth = lineWidth
    }

    /// Keeps the value in `0...1`, treating NaN as no progress.
    nonisolated static func clamped(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, 0), 1)
    }

    public var body: some View {
        ZStack {
            Circle().stroke(DSColor.border, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(DSColor.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: progress)
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(DSFont.caption.monospacedDigit())
                .foregroundStyle(DSColor.textPrimary)
        }
        .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Progresso", bundle: .module))
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

/// Loading placeholder; the shimmer is disabled when Reduce Motion is on.
public struct SkeletonView: View {
    private let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    public init(height: CGFloat = 16) {
        self.height = height
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: Radius.small)
            .fill(DSColor.border)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .opacity(isDimmed ? 0.4 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isDimmed = true
                }
            }
            .accessibilityLabel(Text("Carregando", bundle: .module))
    }
}
