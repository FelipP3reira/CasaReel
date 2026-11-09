import Foundation
import Testing
@testable import Domain

struct DeepLinkParserTests {
    private let parser = DeepLinkParser(host: "casareel.example")
    private static let id = UUID(uuidString: "3F2504E0-4F89-11D3-9A0C-0305E82C3301")

    @Test func parsesKnownRoutes() throws {
        let id = try #require(Self.id)
        let cases: [(String, AppRoute)] = [
            ("https://casareel.example/app/properties", .propertyList),
            ("https://casareel.example/app/properties/\(id.uuidString)", .propertyDetail(id: id)),
            ("https://CasaReel.Example/app/subscription", .subscription),
            ("https://casareel.example/app/privacy", .privacy),
            ("https://casareel.example/app/settings", .settings),
            ("https://casareel.example/app/create", .photoPicker),
            ("https://casareel.example/app/editor", .videoEditor),
        ]
        for (link, route) in cases {
            let url = try #require(URL(string: link))
            #expect(parser.route(for: url) == route, "\(link)")
        }
    }

    @Test(arguments: [
        "http://casareel.example/app/properties",
        "https://evil.example/app/properties",
        "https://casareel.example.evil.example/app/properties",
        "https://user:pass@casareel.example/app/properties",
        "https://casareel.example:8443/app/properties",
        "https://casareel.example/properties",
        "https://casareel.example/app",
        "https://casareel.example/app/",
        "https://casareel.example/app/properties/",
        "https://casareel.example/app//properties",
        "https://casareel.example/app/properties/not-a-uuid",
        "https://casareel.example/app/properties/3F2504E0-4F89-11D3-9A0C-0305E82C3301/edit",
        "https://casareel.example/app/unknown",
        "casareel://app/properties",
    ])
    func rejectsInvalidLinks(_ link: String) throws {
        let url = try #require(URL(string: link))
        #expect(parser.route(for: url) == nil)
    }
}

@MainActor
struct RouterTests {
    private let parser = DeepLinkParser(host: "casareel.example")

    @Test func pushAndPopOnSelectedTab() throws {
        let router = Router()
        let id = UUID()
        router.push(.propertyDetail(id: id))
        router.push(.settings)
        #expect(router.path(for: .properties) == [.propertyDetail(id: id), .settings])

        router.pop()
        #expect(router.path(for: .properties) == [.propertyDetail(id: id)])
        router.pop()
        router.pop()
        #expect(router.path(for: .properties).isEmpty)
    }

    @Test func stacksAreIndependentPerTab() {
        let router = Router()
        router.push(.propertyList)
        router.selectedTab = .account
        router.push(.privacy)
        #expect(router.path(for: .properties) == [.propertyList])
        #expect(router.path(for: .account) == [.privacy])

        router.popToRoot()
        #expect(router.path(for: .account).isEmpty)
        #expect(router.path(for: .properties) == [.propertyList])
    }

    @Test func authIsNeverPushed() {
        let router = Router()
        router.push(.auth)
        #expect(router.path(for: .properties).isEmpty)
    }

    @Test func opensNonSensitiveLinkWhenSignedIn() throws {
        let router = Router(selectedTab: .create)
        let id = UUID()
        let url = try #require(URL(string: "https://casareel.example/app/properties/\(id.uuidString)"))

        #expect(router.open(url, parser: parser, session: .signedIn) == .opened(.propertyDetail(id: id)))
        #expect(router.selectedTab == .properties)
        #expect(router.path(for: .properties) == [.propertyDetail(id: id)])
    }

    @Test func propertyListLinkShowsTabRoot() throws {
        let router = Router()
        router.push(.propertyDetail(id: UUID()))
        let url = try #require(URL(string: "https://casareel.example/app/properties"))

        #expect(router.open(url, parser: parser, session: .signedIn) == .opened(.propertyList))
        #expect(router.path(for: .properties).isEmpty)
    }

    @Test(arguments: [SessionState.signedOut, .revoked])
    func rejectsLinkWithoutValidSession(_ session: SessionState) throws {
        let router = Router()
        let url = try #require(URL(string: "https://casareel.example/app/subscription"))

        #expect(router.open(url, parser: parser, session: session) == .rejectedNoSession)
        #expect(router.paths.isEmpty)
        #expect(router.selectedTab == .properties)
    }

    @Test(arguments: ["privacy", "settings", "create", "editor"])
    func rejectsSensitiveRoutesEvenWhenSignedIn(_ path: String) throws {
        let router = Router()
        let url = try #require(URL(string: "https://casareel.example/app/\(path)"))

        #expect(router.open(url, parser: parser, session: .signedIn) == .rejectedSensitive)
        #expect(router.paths.isEmpty)
    }

    @Test func ignoresInvalidLink() throws {
        let router = Router()
        let url = try #require(URL(string: "https://evil.example/app/properties"))

        #expect(router.open(url, parser: parser, session: .signedIn) == .rejectedInvalid)
        #expect(router.paths.isEmpty)
    }

    @Test func resetClearsNavigation() {
        let router = Router()
        router.selectedTab = .account
        router.push(.settings)
        router.reset()
        #expect(router.selectedTab == .properties)
        #expect(router.paths.isEmpty)
    }
}

@MainActor
struct SessionStoreTests {
    @Test func transitions() {
        let session = SessionStore()
        #expect(session.state == .signedOut)
        session.signIn()
        #expect(session.state == .signedIn)
        session.revoke()
        #expect(session.state == .revoked)
        session.signOut()
        #expect(session.state == .signedOut)
    }
}
