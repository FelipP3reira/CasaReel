import CoreGraphics
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

/// Analyzer double: the photo's file name decides room and faces (e.g. `kitchen-1`, `bedroom-face`).
final class FakeAnalyzer: PhotoAnalyzing {
    private let blurs = OSAllocatedUnfairLock(initialState: 0)
    var blurCalls: Int { blurs.withLock { $0 } }

    func analyze(_ photo: PreparedPhoto) async throws -> AnalysisResult {
        let name = photo.fileURL.lastPathComponent
        let room = RoomType.allCases.first { name.hasPrefix($0.rawValue) } ?? .other
        return AnalysisResult(
            photoID: photo.id, qualityScore: name.contains("blurry") ? 0.2 : 0.9, sharpness: 0.5, exposure: 0.5, noise: 2,
            warnings: name.contains("blurry") ? [.blurry] : [], room: room, roomConfidence: 0.8,
            focus: CGRect(x: 0, y: 0, width: 1, height: 1),
            faces: name.contains("face") ? [CGRect(x: 0.4, y: 0.2, width: 0.1, height: 0.1)] : []
        )
    }

    func blurFaces(in photo: PreparedPhoto, regions: [CGRect]) async throws -> PreparedPhoto {
        blurs.withLock { $0 += 1 }
        return PreparedPhoto(id: photo.id, fileURL: photo.fileURL.appendingPathExtension("blurred"), sha256: "blurred-\(photo.sha256)",
                             size: photo.size, width: photo.width, height: photo.height, mimeType: .jpeg, perceptualHash: photo.perceptualHash)
    }
}

@MainActor
struct PhotoAnalysisIntegrationTests {
    private let preparer = FakePreparer()
    private let analyzer = FakeAnalyzer()

    private func model(_ names: [String]) async -> PhotoSelectionModel {
        let model = PhotoSelectionModel(preparer: preparer, analyzer: analyzer)
        model.add(names.map { FakeSource(name: $0) })
        await model.waitUntilPrepared()
        return model
    }

    @Test func attachesAnalysisAndListsSuggestions() async {
        let model = await model(["kitchen-1", "bedroom-blurry"])

        #expect(model.items.map { $0.analysis?.room } == [.kitchen, .bedroom])
        #expect(model.hasAnalyses)
        #expect(model.suggestions.map(\.position) == [2])
        #expect(model.suggestions.first?.warnings == [.blurry])
    }

    @Test func suggestedOrderFollowsTheStoryAndKeepsRejectedLast() async {
        let model = await model(["bathroom-1", "reject-x", "facade-1", "kitchen-1", "living_room-1"])

        model.applySuggestedOrder()

        let rooms = model.items.map { $0.analysis?.room }
        #expect(rooms == [.facade, .livingRoom, .kitchen, .bathroom, nil])
        if case .rejected = model.items.last?.state {} else { Issue.record("rejected photo should stay at the end") }
    }

    @Test func finalizeBlursFacesOnceWhenEnabled() async {
        let model = await model(["living_room-face", "kitchen-1"])
        #expect(model.hasFaces)

        #expect(await model.finalizedPhotos().allSatisfy { !$0.sha256.hasPrefix("blurred") }, "off by default")

        model.blurFaces = true
        let first = await model.finalizedPhotos()
        let second = await model.finalizedPhotos()

        #expect(analyzer.blurCalls == 1)
        #expect(first.map { $0.sha256.hasPrefix("blurred") } == [true, false])
        #expect(second == first)
        #expect(preparer.discarded.count == 1, "the unblurred original is deleted")
        #expect(model.items[0].analysis?.faces.isEmpty == false, "faces stay known for framing")
    }
}
