import CoreGraphics
import Foundation
import Testing
@testable import Domain

struct ShotOrderPlannerTests {
    private func analysis(_ id: UUID, _ room: RoomType, quality: Double = 0.8) -> AnalysisResult {
        AnalysisResult(
            photoID: id, qualityScore: quality, sharpness: quality, exposure: 0.5, noise: 2, warnings: [],
            room: room, roomConfidence: 0.9, focus: CGRect(x: 0, y: 0, width: 1, height: 1), faces: []
        )
    }

    @Test func ordersRoomsFromFacadeToLeisure() {
        let rooms: [RoomType] = [.pool, .bathroom, .kitchen, .facade, .bedroom, .livingRoom, .other, .balcony]
        let ids = rooms.map { _ in UUID() }
        let analyses = Dictionary(uniqueKeysWithValues: zip(ids, rooms).map { ($0, analysis($0, $1)) })

        let ordered = ShotOrderPlanner.order(photoIDs: ids, analyses: analyses)

        #expect(ordered.compactMap { analyses[$0]?.room } == [.facade, .livingRoom, .kitchen, .bedroom, .bathroom, .balcony, .pool, .other])
    }

    @Test func bestPhotoLeadsItsRoomAndTiesKeepUserOrder() {
        let blurry = UUID(), sharp = UUID(), tieA = UUID(), tieB = UUID()
        let analyses = [
            blurry: analysis(blurry, .bedroom, quality: 0.3),
            sharp: analysis(sharp, .bedroom, quality: 0.9),
            tieA: analysis(tieA, .kitchen, quality: 0.7),
            tieB: analysis(tieB, .kitchen, quality: 0.7),
        ]

        let groups = ShotOrderPlanner.plan(photoIDs: [blurry, tieA, sharp, tieB], analyses: analyses)

        #expect(groups == [
            .init(room: .kitchen, photoIDs: [tieA, tieB]),
            .init(room: .bedroom, photoIDs: [sharp, blurry]),
        ])
    }

    @Test func unanalyzedPhotosGoLastInOriginalOrder() {
        let facade = UUID(), pending1 = UUID(), other = UUID(), pending2 = UUID()
        let analyses = [facade: analysis(facade, .facade), other: analysis(other, .other)]

        let ordered = ShotOrderPlanner.order(photoIDs: [pending1, other, facade, pending2], analyses: analyses)

        #expect(ordered == [facade, other, pending1, pending2])
    }

    @Test func handlesEmptyAndUniformLists() {
        #expect(ShotOrderPlanner.order(photoIDs: [], analyses: [:]).isEmpty)
        let ids = (0..<5).map { _ in UUID() }
        #expect(ShotOrderPlanner.order(photoIDs: ids, analyses: [:]) == ids)
        let same = Dictionary(uniqueKeysWithValues: ids.map { ($0, analysis($0, .livingRoom)) })
        #expect(ShotOrderPlanner.order(photoIDs: ids, analyses: same) == ids)
    }

    @Test func analysisResultRoundTripsAsJSON() throws {
        let id = UUID()
        let result = AnalysisResult(
            photoID: id, qualityScore: 0.42, sharpness: 0.3, exposure: 0.2, noise: 9, warnings: [.blurry, .tooDark],
            room: .kitchen, roomConfidence: 0.6, focus: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4),
            faces: [CGRect(x: 0.4, y: 0.1, width: 0.1, height: 0.1)]
        )
        let decoded = try JSONDecoder().decode(AnalysisResult.self, from: JSONEncoder().encode(result))
        #expect(decoded == result)
        #expect(RoomType.livingRoom.rawValue == "living_room")
    }
}
