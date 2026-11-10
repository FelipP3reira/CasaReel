import Foundation

public enum AppTab: String, CaseIterable, Hashable, Sendable {
    case properties
    case create
    case account
}

public enum AppRoute: Hashable, Sendable {
    case auth
    case propertyList
    case propertyDetail(id: UUID)
    case photoPicker
    case videoEditor
    /// On-device 3D walk-through recorded with ARKit and processed on the iPhone.
    case walk3D
    case subscription
    case privacy
    case settings

    /// Tab that hosts the route; `nil` for routes shown outside the tab bar.
    public var tab: AppTab? {
        switch self {
        case .auth: nil
        case .propertyList, .propertyDetail: .properties
        case .photoPicker, .videoEditor, .walk3D: .create
        case .subscription, .privacy, .settings: .account
        }
    }

    /// Only read-only, non-sensitive screens may be opened from a link.
    /// Editing, privacy (account deletion, data export) and settings never are.
    public var isDeepLinkable: Bool {
        switch self {
        case .propertyList, .propertyDetail, .subscription: true
        case .auth, .photoPicker, .videoEditor, .walk3D, .privacy, .settings: false
        }
    }
}
