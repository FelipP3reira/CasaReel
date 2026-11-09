import SwiftUI
import UIKit

/// Semantic color palette. Every token has a light and a dark variant.
public enum DSColor {
    public static let background = Color(uiColor: uiBackground)
    public static let surface = Color(uiColor: uiSurface)
    public static let textPrimary = Color(uiColor: uiTextPrimary)
    public static let textSecondary = Color(uiColor: uiTextSecondary)
    public static let accent = Color(uiColor: uiAccent)
    public static let onAccent = Color(uiColor: uiOnAccent)
    public static let border = Color(uiColor: uiBorder)
    public static let success = Color(uiColor: uiSuccess)
    public static let warning = Color(uiColor: uiWarning)
    public static let danger = Color(uiColor: uiDanger)

    static let uiBackground = dynamic(light: 0xF7F5F2, dark: 0x121212)
    static let uiSurface = dynamic(light: 0xFFFFFF, dark: 0x1E1E1E)
    static let uiTextPrimary = dynamic(light: 0x1A1A1A, dark: 0xF2F2F2)
    static let uiTextSecondary = dynamic(light: 0x5C5C5C, dark: 0xB3B3B3)
    static let uiAccent = dynamic(light: 0x0B6E4F, dark: 0x4CC79A)
    static let uiOnAccent = dynamic(light: 0xFFFFFF, dark: 0x0A0A0A)
    static let uiBorder = dynamic(light: 0xD9D4CC, dark: 0x3A3A3A)
    static let uiSuccess = dynamic(light: 0x1E7B34, dark: 0x6FD08C)
    static let uiWarning = dynamic(light: 0x8A5A00, dark: 0xF2B84B)
    static let uiDanger = dynamic(light: 0xB3261E, dark: 0xFF8A80)

    private static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
