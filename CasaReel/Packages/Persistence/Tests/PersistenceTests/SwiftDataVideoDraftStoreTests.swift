import Domain
import Foundation
import Testing
@testable import Persistence

struct SwiftDataVideoDraftStoreTests {
    private func draft(caption: String = "Sala", updatedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)) throws -> VideoDraft {
        let slug = try #require(TemplateSlug(rawValue: "classic-clean"))
        let photo = PreparedPhoto(fileURL: URL(filePath: "/tmp/a.jpg"), sha256: "abc", size: 10, width: 1600, height: 1200,
                                  mimeType: .jpeg, perceptualHash: 42)
        return VideoDraft(
            templateSlug: slug, formats: [.vertical, .horizontal],
            scenes: [.init(photo: photo, analysis: nil, caption: caption, durationMs: 3_000)],
            openingText: "Casa de praia", closingText: "Reserve já", updatedAt: updatedAt
        )
    }

    @Test func emptyStoreHasNoDraft() async throws {
        let store = try SwiftDataVideoDraftStore.make(inMemory: true)
        #expect(await store.load() == nil)
    }

    @Test func savesAndRestoresTheDraft() async throws {
        let store = try SwiftDataVideoDraftStore.make(inMemory: true)
        let saved = try draft()
        await store.save(saved)
        #expect(await store.load() == saved)
        #expect(await store.load()?.photoFiles == [URL(filePath: "/tmp/a.jpg")])
    }

    @Test func savingAgainReplacesTheDraft() async throws {
        let store = try SwiftDataVideoDraftStore.make(inMemory: true)
        await store.save(try draft(caption: "Sala"))
        let newer = try draft(caption: "Cozinha", updatedAt: Date(timeIntervalSince1970: 1_800_000_100))
        await store.save(newer)
        #expect(await store.load() == newer)
    }

    @Test func deleteRemovesTheDraft() async throws {
        let store = try SwiftDataVideoDraftStore.make(inMemory: true)
        await store.save(try draft())
        await store.delete()
        #expect(await store.load() == nil)
    }
}
