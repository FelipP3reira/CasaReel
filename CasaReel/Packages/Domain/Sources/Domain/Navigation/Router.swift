import Foundation
import Observation

/// Navigation state: the selected tab and one typed stack per tab.
@Observable
@MainActor
public final class Router {
    public enum DeepLinkOutcome: Equatable, Sendable {
        case opened(AppRoute)
        case rejectedInvalid
        case rejectedSensitive
        case rejectedNoSession
    }

    public var selectedTab: AppTab
    public private(set) var paths: [AppTab: [AppRoute]] = [:]

    public init(selectedTab: AppTab = .properties) {
        self.selectedTab = selectedTab
    }

    public func path(for tab: AppTab) -> [AppRoute] {
        paths[tab] ?? []
    }

    public func setPath(_ path: [AppRoute], for tab: AppTab) {
        paths[tab] = path
    }

    /// Pushes onto the current tab's stack. `auth` is never pushed; it is driven by the session.
    public func push(_ route: AppRoute) {
        guard route != .auth else { return }
        paths[selectedTab, default: []].append(route)
    }

    public func pop() {
        guard paths[selectedTab]?.isEmpty == false else { return }
        paths[selectedTab]?.removeLast()
    }

    public func popToRoot() {
        paths[selectedTab] = []
    }

    public func reset() {
        selectedTab = .properties
        paths = [:]
    }

    /// Opens a Universal Link only for a signed-in user and a non-sensitive route.
    @discardableResult
    public func open(_ url: URL, parser: DeepLinkParser, session: SessionState) -> DeepLinkOutcome {
        guard let route = parser.route(for: url), let tab = route.tab else { return .rejectedInvalid }
        guard route.isDeepLinkable else { return .rejectedSensitive }
        guard session == .signedIn else { return .rejectedNoSession }

        selectedTab = tab
        paths[tab] = route == .propertyList ? [] : [route]
        return .opened(route)
    }
}
