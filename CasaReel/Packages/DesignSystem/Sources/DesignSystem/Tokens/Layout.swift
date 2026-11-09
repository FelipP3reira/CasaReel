import SwiftUI

/// Spacing scale shared by every screen.
public enum Spacing {
    public static let xSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 24
    public static let xLarge: CGFloat = 32
}

public enum Radius {
    public static let small: CGFloat = 6
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 20
}

/// Minimum hit target recommended by the Human Interface Guidelines.
public enum TouchTarget {
    public static let minimum: CGFloat = 44
}

public struct DSShadow: Sendable {
    public let radius: CGFloat
    public let y: CGFloat
    public let opacity: Double

    public static let card = DSShadow(radius: 8, y: 2, opacity: 0.08)
    public static let floating = DSShadow(radius: 16, y: 6, opacity: 0.16)
}

extension View {
    public func dsShadow(_ shadow: DSShadow) -> some View {
        self.shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, x: 0, y: shadow.y)
    }
}
