import Testing
import UIKit
@testable import DesignSystem

struct ValidationRuleTests {
    @Test(arguments: ["", "   ", "\n"])
    func requiredRejectsBlank(_ value: String) {
        #expect(!ValidationRule.required.validate(value))
    }

    @Test func requiredAcceptsText() {
        #expect(ValidationRule.required.validate("Casa de praia"))
    }

    @Test func minLengthIgnoresSurroundingWhitespace() {
        let rule = ValidationRule.minLength(3)
        #expect(!rule.validate("  ab  "))
        #expect(rule.validate("abc"))
    }

    @Test(arguments: ["ana@exemplo.com", " ana.silva+casa@exemplo.com.br "])
    func emailAcceptsValidAddresses(_ value: String) {
        #expect(ValidationRule.email.validate(value))
    }

    @Test(arguments: ["ana", "ana@", "@exemplo.com", "ana@exemplo", "ana @exemplo.com"])
    func emailRejectsInvalidAddresses(_ value: String) {
        #expect(!ValidationRule.email.validate(value))
    }

    @Test func firstFailureReturnsTheFirstBrokenRuleInOrder() {
        let rules: [ValidationRule] = [.required, .email]
        #expect(ValidationRule.firstFailure(in: rules, for: "")?.message.key == "Campo obrigatório")
        #expect(ValidationRule.firstFailure(in: rules, for: "ana")?.message.key == "E-mail inválido")
        #expect(ValidationRule.firstFailure(in: rules, for: "ana@exemplo.com") == nil)
    }
}

struct ProgressRingTests {
    @Test(arguments: [(-1.0, 0.0), (0.42, 0.42), (2.0, 1.0), (Double.nan, 0.0)])
    func clampsProgress(input: Double, expected: Double) {
        #expect(ProgressRing.clamped(input) == expected)
    }
}

@MainActor
struct ToastCenterTests {
    @Test func showReplacesCurrentToast() {
        let center = ToastCenter()
        let first = ToastMessage("Primeiro")
        let second = ToastMessage("Segundo", style: .success)
        center.show(first)
        center.show(second)
        #expect(center.current == second)
    }

    @Test func dismissClearsToast() {
        let center = ToastCenter()
        center.show(ToastMessage("Salvo"))
        center.dismiss()
        #expect(center.current == nil)
    }

    @Test func toastDismissesItselfAfterDuration() async throws {
        let center = ToastCenter()
        center.show(ToastMessage("Salvo"), duration: .milliseconds(20))
        try await Task.sleep(for: .milliseconds(300))
        #expect(center.current == nil)
    }
}

/// Checks WCAG 2.1 contrast for the text/background pairs used by the components.
struct ColorContrastTests {
    static let pairs: [(name: String, foreground: UIColor, background: UIColor, minimum: Double)] = [
        ("textPrimary/background", DSColor.uiTextPrimary, DSColor.uiBackground, 4.5),
        ("textSecondary/surface", DSColor.uiTextSecondary, DSColor.uiSurface, 4.5),
        ("textSecondary/background", DSColor.uiTextSecondary, DSColor.uiBackground, 4.5),
        ("onAccent/accent", DSColor.uiOnAccent, DSColor.uiAccent, 4.5),
        ("accent/surface", DSColor.uiAccent, DSColor.uiSurface, 4.5),
        ("danger/surface", DSColor.uiDanger, DSColor.uiSurface, 4.5),
        ("success/surface", DSColor.uiSuccess, DSColor.uiSurface, 4.5),
        ("warning/surface", DSColor.uiWarning, DSColor.uiSurface, 4.5),
    ]

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func pairsMeetMinimumContrast(style: UIUserInterfaceStyle) {
        let traits = UITraitCollection(userInterfaceStyle: style)
        for pair in Self.pairs {
            let ratio = contrastRatio(
                pair.foreground.resolvedColor(with: traits),
                pair.background.resolvedColor(with: traits)
            )
            #expect(ratio >= pair.minimum, "\(pair.name) in \(style == .dark ? "dark" : "light"): \(ratio)")
        }
    }

    @Test func tokensChangeBetweenLightAndDark() {
        let light = DSColor.uiBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = DSColor.uiBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(light != dark)
    }

    private func contrastRatio(_ first: UIColor, _ second: UIColor) -> Double {
        let lighter = max(luminance(first), luminance(second))
        let darker = min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func luminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func linear(_ channel: CGFloat) -> Double {
            let value = Double(channel)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
