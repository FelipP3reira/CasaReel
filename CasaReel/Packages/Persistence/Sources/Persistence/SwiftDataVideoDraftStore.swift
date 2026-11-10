import Domain
import Foundation
import SwiftData

/// One saved draft. The draft is stored as JSON so its shape can evolve without SwiftData migrations.
@Model
final class VideoDraftRecord {
    var updatedAt: Date
    var payload: Data

    init(updatedAt: Date, payload: Data) {
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

/// SwiftData store for the single current video draft.
@ModelActor
public actor SwiftDataVideoDraftStore: VideoDraftStoring {
    /// On-disk store in Application Support (excluded from backup), or in memory for tests.
    public static func make(inMemory: Bool = false) throws -> SwiftDataVideoDraftStore {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            var directory = URL.applicationSupportDirectory.appending(path: "CasaReelDrafts", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            configuration = ModelConfiguration(url: directory.appending(path: "drafts.store"))
        }
        let container = try ModelContainer(for: VideoDraftRecord.self, configurations: configuration)
        return SwiftDataVideoDraftStore(modelContainer: container)
    }

    public func load() async -> VideoDraft? {
        var descriptor = FetchDescriptor<VideoDraftRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let record = try? modelContext.fetch(descriptor).first else { return nil }
        // An unreadable draft (older app version, corruption) is dropped rather than crashing the editor.
        guard let draft = try? JSONDecoder().decode(VideoDraft.self, from: record.payload) else {
            await delete()
            return nil
        }
        return draft
    }

    public func save(_ draft: VideoDraft) async {
        guard let payload = try? JSONEncoder().encode(draft) else { return }
        let existing = (try? modelContext.fetch(FetchDescriptor<VideoDraftRecord>())) ?? []
        if let record = existing.first {
            record.payload = payload
            record.updatedAt = draft.updatedAt
            existing.dropFirst().forEach(modelContext.delete)
        } else {
            modelContext.insert(VideoDraftRecord(updatedAt: draft.updatedAt, payload: payload))
        }
        try? modelContext.save()
    }

    public func delete() async {
        try? modelContext.delete(model: VideoDraftRecord.self)
        try? modelContext.save()
    }
}
