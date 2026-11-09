import Foundation
import SwiftUI

/// A validation rule evaluated against a text field value.
public struct ValidationRule: Sendable {
    public let message: LocalizedStringResource
    private let isValid: @Sendable (String) -> Bool

    public init(message: LocalizedStringResource, isValid: @escaping @Sendable (String) -> Bool) {
        self.message = message
        self.isValid = isValid
    }

    public func validate(_ value: String) -> Bool {
        isValid(value)
    }

    public static let required = ValidationRule(message: dsString("Campo obrigatório")) {
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func minLength(_ length: Int) -> ValidationRule {
        ValidationRule(message: dsString("Texto muito curto")) {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).count >= length
        }
    }

    public static let email = ValidationRule(message: dsString("E-mail inválido")) { value in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]{2,}/) != nil
    }

    /// Returns the message of the first rule that fails, or `nil` when the value is valid.
    public static func firstFailure(in rules: [ValidationRule], for value: String) -> ValidationRule? {
        rules.first { !$0.validate(value) }
    }
}

/// Labelled text field that shows its validation error once the user has edited it.
public struct TextFieldRow: View {
    private let label: LocalizedStringResource
    private let prompt: LocalizedStringResource?
    @Binding private var text: String
    private let rules: [ValidationRule]
    @State private var hasEdited = false

    public init(
        _ label: LocalizedStringResource,
        text: Binding<String>,
        prompt: LocalizedStringResource? = nil,
        rules: [ValidationRule] = []
    ) {
        self.label = label
        self._text = text
        self.prompt = prompt
        self.rules = rules
    }

    private var error: LocalizedStringResource? {
        guard hasEdited else { return nil }
        return ValidationRule.firstFailure(in: rules, for: text)?.message
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(label)
                .font(DSFont.callout.weight(.medium))
                .foregroundStyle(DSColor.textPrimary)
            TextField(text: $text, prompt: prompt.map { Text($0) }) {
                Text(label)
            }
            .font(DSFont.body)
            .padding(.horizontal, Spacing.medium)
            .frame(minHeight: TouchTarget.minimum)
            .background(RoundedRectangle(cornerRadius: Radius.small).fill(DSColor.surface))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.small)
                    .strokeBorder(error == nil ? DSColor.border : DSColor.danger, lineWidth: 1)
            )
            .onChange(of: text) { hasEdited = true }
            .accessibilityHint(error.map { Text($0) } ?? Text(verbatim: ""))
            if let error {
                Label { Text(error) } icon: { Image(systemName: "exclamationmark.circle.fill") }
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.danger)
            }
        }
    }
}
