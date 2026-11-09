import SwiftUI

/// Typography built on system text styles so every size follows Dynamic Type.
public enum DSFont {
    public static let largeTitle = Font.largeTitle.bold()
    public static let title = Font.title2.bold()
    public static let headline = Font.headline
    public static let body = Font.body
    public static let callout = Font.callout
    public static let caption = Font.caption
    public static let button = Font.body.weight(.semibold)
}
