import Foundation

/// Maps Universal Links (`https://<host>/app/...`) to routes. Anything unexpected yields `nil`.
public struct DeepLinkParser: Sendable {
    private let host: String

    public init(host: String) {
        self.host = host.lowercased()
    }

    public func route(for url: URL) -> AppRoute? {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "https",
            components.host?.lowercased() == host,
            components.user == nil,
            components.password == nil,
            components.port == nil
        else { return nil }

        // "/app/properties/<id>" -> ["app", "properties", "<id>"]; empty segments (e.g. "//") are rejected.
        let segments = components.path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
        guard segments.count >= 2, segments.count <= 3, segments[0] == "app", !segments.contains("") else { return nil }

        if segments.count == 3 {
            guard segments[1] == "properties", let id = UUID(uuidString: segments[2]) else { return nil }
            return .propertyDetail(id: id)
        }
        return Self.staticRoutes[segments[1]]
    }

    private static let staticRoutes: [String: AppRoute] = [
        "properties": .propertyList,
        "create": .photoPicker,
        "editor": .videoEditor,
        "subscription": .subscription,
        "privacy": .privacy,
        "settings": .settings,
    ]
}
