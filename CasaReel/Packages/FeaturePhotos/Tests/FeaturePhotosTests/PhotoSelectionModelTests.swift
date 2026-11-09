import Domain
import Foundation
import os
import Testing
@testable import FeaturePhotos

/// Preparer double: the staged file's name decides the outcome (`reject-*`, `dup-*`, anything else = ok).
final class FakePreparer: PhotoPreparing {
    let stagingDirectory = FileManager.default.temporaryDirectory.appending(path: "FeaturePhotosTests-\(UUID().uuidString)")
    private let state = OSAllocatedUnfairLock(initialState: (discarded: [UUID](), discardAllCalls: 0))

    var discarded: [UUID] { state.withLock { $0.discarded } }
    var discardAllCalls: Int { state.withLock { $0.discardAllCalls } }

    func prepare(fileAt url: URL) async throws(PhotoRejection) -> PreparedPhoto {
        try? await Task.sleep(for: .milliseconds(5))
        let name = url.lastPathComponent
        if name.hasPrefix("reject") { throw .tooSmall }
        let sha = name.hasPrefix("dup") ? "same" : name
        return PreparedPhoto(fileURL: url, sha256: sha, size: 1, width: 1600, height: 1200, mimeType: .jpeg,
                             perceptualHash: name.hasPrefix("dup") ? 0 : UInt64(abs(name.hashValue)) | 0xFFFF)
    }

    func discard(_ photo: PreparedPhoto) {
        state.withLock { $0.discarded.append(photo.id) }
    }

    func discardAll() {
        state.withLock { $0.discardAllCalls += 1 }
    }
}

struct FakeSource: PhotoSource {
    let name: String
    var fails = false

    func stage(into directory: URL) async throws -> URL {
        if fails { throw CocoaError(.fileReadUnknown) }
        return directory.appending(path: name)
    }
}

@MainActor
struct PhotoSelectionModelTests {
    private let preparer = FakePreparer()

    private func sources(_ count: Int, prefix: String = "photo") -> [any PhotoSource] {
        (0..<count).map { FakeSource(name: "\(prefix)-\($0)") }
    }

    @Test func preparesPhotosInPickOrder() async {
        let model = PhotoSelectionModel(preparer: preparer)
        model.add(sources(3))
        #expect(model.isPreparing)

        await model.waitUntilPrepared()

        #expect(!model.isPreparing)
        #expect(model.readyPhotos.map { $0.fileURL.lastPathComponent } == ["photo-0", "photo-1", "photo-2"])
    }

    @Test func requiresBetweenFiveAndFortyReadyPhotos() async {
        let model = PhotoSelectionModel(preparer: preparer)
        model.add(sources(4))
        await model.waitUntilPrepared()
        #expect(!model.canContinue)

        model.add(sources(1, prefix: "extra"))
        await model.waitUntilPrepared()
        #expect(model.canContinue)
    }

    @Test func capsSelectionAtForty() async {
        let model = PhotoSelectionModel(preparer: preparer)
        model.add(sources(45))
        await model.waitUntilPrepared()

        #expect(model.items.count == PhotoLimits.maximumCount)
        #expect(model.remainingSlots == 0)
        #expect(model.canContinue)
    }

    @Test func rejectedPhotosShowReasonAndFreeTheirSlot() async {
        let model = PhotoSelectionModel(preparer: preparer)
        model.add([FakeSource(name: "reject-a"), FakeSource(name: "broken", fails: true), FakeSource(name: "ok")])
        await model.waitUntilPrepared()

        #expect(model.items.map(\.state).contains(.rejected(.tooSmall)))
        #expect(model.items.map(\.state).contains(.rejected(.unreadable)))
        #expect(model.rejectedCount == 2)
        #expect(model.remainingSlots == PhotoLimits.maximumCount - 1)

        model.removeRejected()
        #expect(model.items.count == 1)
    }

    @Test func flagsLaterDuplicatesOnly() async {
        let model = PhotoSelectionModel(preparer: preparer)
        model.add([FakeSource(name: "dup-1"), FakeSource(name: "unique"), FakeSource(name: "dup-2")])
        await model.waitUntilPrepared()

        #expect(model.items.map(\.duplicate) == [nil, nil, .exact])

        model.remove(model.items[0].id)
        #expect(model.items.map(\.duplicate) == [nil, nil], "the remaining copy is no longer a duplicate")
    }

    @Test func removeDiscardsThePreparedFile() async {
        let model = PhotoSelectionModel(preparer: preparer)
        model.add(sources(2))
        await model.waitUntilPrepared()
        let removed = model.readyPhotos[0]

        model.remove(model.items[0].id)

        #expect(preparer.discarded == [removed.id])
        #expect(model.readyPhotos.count == 1)
    }

    @Test func dragMovesPhotoToTargetPosition() async {
        let model = PhotoSelectionModel(preparer: preparer)
        model.add(sources(3))
        await model.waitUntilPrepared()
        let ids = model.items.map(\.id)

        model.move(ids[2], to: ids[0])
        #expect(model.items.map(\.id) == [ids[2], ids[0], ids[1]])

        model.move(ids[2], to: ids[2])
        model.move(UUID(), to: ids[0])
        #expect(model.items.map(\.id) == [ids[2], ids[0], ids[1]])
    }

    @Test func resetCancelsWorkAndDeletesTemporaryFiles() async {
        let model = PhotoSelectionModel(preparer: preparer)
        model.add(sources(10))
        model.reset()
        await model.waitUntilPrepared()

        #expect(model.items.isEmpty)
        #expect(preparer.discardAllCalls == 1)

        model.add(sources(1))
        await model.waitUntilPrepared()
        #expect(model.readyPhotos.count == 1, "the model keeps working after a reset")
    }

    @Test func rejectionMessagesExistForEveryReason() {
        let reasons: [PhotoRejection] = [.unsupportedType, .fileTooLarge, .tooSmall, .tooManyPixels, .unreadable]
        let messages = Set(reasons.map { String(localized: $0.message) })
        #expect(messages.count == reasons.count)
        #expect(!messages.contains(""))
    }
}
