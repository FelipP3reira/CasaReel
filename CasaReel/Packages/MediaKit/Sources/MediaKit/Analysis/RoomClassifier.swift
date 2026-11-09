import CoreGraphics
import Domain
import Foundation
import Vision

/// Extension point: a signed Core ML model (`.mlpackage`) can replace the Vision taxonomy later.
public protocol RoomClassifying: Sendable {
    func classify(_ image: CGImage) -> (room: RoomType, confidence: Double)
}

/// Maps Apple's built-in image taxonomy (`VNClassifyImageRequest`) onto our room types.
public struct VisionRoomClassifier: RoomClassifying {
    /// Labels that vote for each room; matched against whole identifiers or their `_`-separated words.
    static let keywords: [RoomType: Set<String>] = [
        .kitchen: ["kitchen", "stove", "oven", "refrigerator", "countertop", "microwave", "dishwasher"],
        .bedroom: ["bedroom", "bed", "pillow", "bedding", "quilt", "headboard"],
        .bathroom: ["bathroom", "bathtub", "toilet", "shower", "washbasin", "towel"],
        .livingRoom: ["living_room", "sofa", "couch", "fireplace", "armchair", "coffee_table", "television"],
        .pool: ["swimming_pool", "pool", "jacuzzi"],
        .balcony: ["balcony", "patio", "terrace", "porch", "deck", "veranda", "garden", "hammock"],
        .facade: ["house", "facade", "building", "residential", "villa", "cottage", "cabin", "exterior", "roof"],
    ]
    /// Below this summed confidence the photo is labelled `.other`.
    static let minimumConfidence = 0.15

    public init() {}

    public func classify(_ image: CGImage) -> (room: RoomType, confidence: Double) {
        let request = VNClassifyImageRequest()
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            return (.other, 0)
        }
        let observations = (request.results ?? []).map { ($0.identifier, Double($0.confidence)) }
        return Self.room(for: observations)
    }

    /// Sums the confidence of every matching label per room and picks the strongest.
    static func room(for observations: [(identifier: String, confidence: Double)]) -> (room: RoomType, confidence: Double) {
        var votes: [RoomType: Double] = [:]
        for (identifier, confidence) in observations where confidence > 0.05 {
            let label = identifier.lowercased()
            let words = Set(label.split(separator: "_").map(String.init))
            for (room, keys) in keywords where keys.contains(label) || !keys.isDisjoint(with: words) {
                votes[room, default: 0] += confidence
            }
        }
        // Ties are broken by the storytelling order so results are deterministic.
        let best = ShotOrderPlanner.roomSequence.compactMap { room in votes[room].map { (room, $0) } }
            .max { $0.1 < $1.1 }
        guard let best, best.1 >= minimumConfidence else { return (.other, best?.1 ?? 0) }
        return (best.0, min(best.1, 1))
    }
}
