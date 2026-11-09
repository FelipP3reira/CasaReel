import CoreGraphics
import Foundation

/// Room categories used for captions and the shot order. Raw values match the API's `roomType`.
public enum RoomType: String, Codable, Sendable, CaseIterable {
    case facade
    case livingRoom = "living_room"
    case kitchen
    case bedroom
    case bathroom
    case balcony
    case pool
    case other
}

public enum QualityWarning: String, Codable, Sendable, CaseIterable {
    case blurry
    case tooDark = "too_dark"
    case tooBright = "too_bright"
    case noisy
}

/// On-device analysis of one prepared photo. Scores and labels only: never pixels or location.
public struct AnalysisResult: Codable, Sendable, Equatable {
    public let photoID: UUID
    /// Overall 0–1 (1 = best), combining sharpness, exposure and noise.
    public let qualityScore: Double
    /// 0–1, higher is sharper.
    public let sharpness: Double
    /// Mean luminance 0–1.
    public let exposure: Double
    /// Estimated noise standard deviation on a 0–255 scale.
    public let noise: Double
    public let warnings: [QualityWarning]
    public let room: RoomType
    public let roomConfidence: Double
    /// Region of interest for pan/zoom, normalized with a top-left origin.
    public let focus: CGRect
    /// Face rectangles, normalized with a top-left origin.
    public let faces: [CGRect]

    public init(
        photoID: UUID, qualityScore: Double, sharpness: Double, exposure: Double, noise: Double,
        warnings: [QualityWarning], room: RoomType, roomConfidence: Double, focus: CGRect, faces: [CGRect]
    ) {
        self.photoID = photoID
        self.qualityScore = qualityScore
        self.sharpness = sharpness
        self.exposure = exposure
        self.noise = noise
        self.warnings = warnings
        self.room = room
        self.roomConfidence = roomConfidence
        self.focus = focus
        self.faces = faces
    }
}

/// Analyzes prepared photos on the device (implemented by `MediaKit`). No network, no external models.
public protocol PhotoAnalyzing: Sendable {
    func analyze(_ photo: PreparedPhoto) async throws -> AnalysisResult
    /// Writes a new sanitized copy with the given normalized regions blurred.
    func blurFaces(in photo: PreparedPhoto, regions: [CGRect]) async throws -> PreparedPhoto
}

/// Suggested storytelling order: outside first, then the social areas, private rooms and leisure.
public enum ShotOrderPlanner {
    public static let roomSequence: [RoomType] = [.facade, .livingRoom, .kitchen, .bedroom, .bathroom, .balcony, .pool, .other]

    public struct Group: Sendable, Equatable {
        public let room: RoomType
        public let photoIDs: [UUID]
    }

    /// Groups photos by room in `roomSequence` order; inside a room the best photo comes first,
    /// and ties keep the user's original order. Photos without analysis go last, in their original order.
    public static func plan(photoIDs: [UUID], analyses: [UUID: AnalysisResult]) -> [Group] {
        let originalIndex = Dictionary(uniqueKeysWithValues: photoIDs.enumerated().map { ($1, $0) })
        var groups: [Group] = roomSequence.compactMap { room in
            let ids = photoIDs
                .filter { analyses[$0]?.room == room }
                .sorted { lhs, rhs in
                    let left = analyses[lhs]?.qualityScore ?? 0, right = analyses[rhs]?.qualityScore ?? 0
                    return left != right ? left > right : (originalIndex[lhs] ?? 0) < (originalIndex[rhs] ?? 0)
                }
            return ids.isEmpty ? nil : Group(room: room, photoIDs: ids)
        }
        let unanalyzed = photoIDs.filter { analyses[$0] == nil }
        if !unanalyzed.isEmpty {
            if let index = groups.firstIndex(where: { $0.room == .other }) {
                groups[index] = Group(room: .other, photoIDs: groups[index].photoIDs + unanalyzed)
            } else {
                groups.append(Group(room: .other, photoIDs: unanalyzed))
            }
        }
        return groups
    }

    public static func order(photoIDs: [UUID], analyses: [UUID: AnalysisResult]) -> [UUID] {
        plan(photoIDs: photoIDs, analyses: analyses).flatMap(\.photoIDs)
    }
}
