import Foundation
import simd

/// One rendered viewpoint. Axes follow COLMAP/OpenCV: the camera looks along +z, y points down on screen.
public struct CameraPose: Sendable, Equatable {
    public var position: SIMD3<Float>
    /// Unit vector the camera looks along.
    public var forward: SIMD3<Float>
    /// Unit vector pointing up in the world (screen up).
    public var up: SIMD3<Float>
    /// Vertical field of view, radians.
    public var fovY: Float
}

/// The camera poses COLMAP recovered (`path.json` from `convert.py`), turned into a smooth walk.
struct CameraPath {
    struct File: Decodable {
        struct Pose: Decodable {
            let image: String
            let position: [Float]
            let rotation: [[Float]]
            let fovY: Float
        }

        struct Segment: Decodable {
            let name: String
            let frames: [Pose]
        }

        let format: String
        let version: Int
        let segments: [Segment]
        let photos: [Pose]
    }

    /// Raw poses in walk order: video frames in time order, or photos chained by proximity when there is no video.
    let keyframes: [CameraPose]

    init(contentsOf url: URL) throws(Walk3DImportError) {
        guard let data = try? Data(contentsOf: url) else { throw .invalidPath }
        try self.init(data: data)
    }

    init(data: Data) throws(Walk3DImportError) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let file = try? decoder.decode(File.self, from: data), file.format == "casareel-walk3d-path", file.version == 1 else {
            throw .invalidPath
        }
        let videoPoses = file.segments.flatMap(\.frames).compactMap(Self.pose)
        let poses = videoPoses.count >= 2 ? videoPoses : Self.chainedByProximity(file.photos.compactMap(Self.pose))
        guard poses.count >= 2 else { throw .invalidPath }
        try self.init(keyframes: poses)
    }

    init(keyframes: [CameraPose]) throws(Walk3DImportError) {
        guard keyframes.count >= 2 else { throw .invalidPath }
        self.keyframes = keyframes
    }

    private static func pose(_ pose: File.Pose) -> CameraPose? {
        guard pose.position.count == 3, pose.rotation.count == 3, pose.rotation.allSatisfy({ $0.count == 3 }),
              (pose.position + pose.rotation.flatMap { $0 } + [pose.fovY]).allSatisfy(\.isFinite)
        else { return nil }
        // Columns of camera-to-world are the camera axes in world space: x right, y down, z forward.
        let down = SIMD3(pose.rotation[0][1], pose.rotation[1][1], pose.rotation[2][1])
        let forward = SIMD3(pose.rotation[0][2], pose.rotation[1][2], pose.rotation[2][2])
        guard simd_length(forward) > 0.5 else { return nil }
        return CameraPose(position: SIMD3(pose.position[0], pose.position[1], pose.position[2]),
                          forward: simd_normalize(forward), up: simd_normalize(-down), fovY: min(max(pose.fovY, 0.5), 1.6))
    }

    /// Greedy nearest-neighbor chain, starting from the first photo.
    static func chainedByProximity(_ poses: [CameraPose]) -> [CameraPose] {
        guard var current = poses.first else { return [] }
        var remaining = Array(poses.dropFirst())
        var chain = [current]
        while !remaining.isEmpty {
            let nearest = remaining.indices.min { simd_distance(remaining[$0].position, current.position) < simd_distance(remaining[$1].position, current.position) } ?? 0
            current = remaining.remove(at: nearest)
            chain.append(current)
        }
        return chain
    }

    /// Smoothed walk with `frameCount` poses at constant speed along the path.
    ///
    /// Hand-held video shakes and rolls; a walkthrough should glide. Positions and view directions are
    /// averaged over neighbors, the horizon is leveled with one "up" for the whole scene, and frames are
    /// spaced by distance so the camera neither stops nor rushes.
    func walk(frameCount: Int, smoothing: Int = 8) -> [CameraPose] {
        guard frameCount > 0 else { return [] }
        let up = simd_normalize(keyframes.reduce(SIMD3<Float>()) { $0 + $1.up })
        let smoothed = keyframes.indices.map { index -> CameraPose in
            let range = max(0, index - smoothing)...min(keyframes.count - 1, index + smoothing)
            let position = range.reduce(SIMD3<Float>()) { $0 + keyframes[$1].position } / Float(range.count)
            var forward = range.reduce(SIMD3<Float>()) { $0 + keyframes[$1].forward }
            // Roll is removed by using one `up` for the whole scene, which levels the horizon.
            forward = simd_length(forward) > 1e-4 ? simd_normalize(forward) : keyframes[index].forward
            return CameraPose(position: position, forward: forward, up: up, fovY: keyframes[index].fovY)
        }
        let fovY = smoothed.map(\.fovY).sorted()[smoothed.count / 2]
        // Cumulative distance; a path that never moves falls back to spacing by index.
        var distances: [Float] = [0]
        for index in 1..<smoothed.count {
            distances.append(distances[index - 1] + simd_distance(smoothed[index].position, smoothed[index - 1].position))
        }
        let total = distances.last ?? 0
        if total < 1e-5 { distances = smoothed.indices.map(Float.init) }
        let length = distances.last ?? 1
        var segment = 0
        return (0..<frameCount).map { frame in
            let target = frameCount == 1 ? 0 : length * Float(frame) / Float(frameCount - 1)
            while segment < distances.count - 2, distances[segment + 1] < target { segment += 1 }
            let span = distances[segment + 1] - distances[segment]
            let t = span > 0 ? min(max((target - distances[segment]) / span, 0), 1) : 0
            let a = smoothed[segment], b = smoothed[segment + 1]
            let forward = simd_normalize(simd_mix(a.forward, b.forward, SIMD3(repeating: t)))
            return CameraPose(position: simd_mix(a.position, b.position, SIMD3(repeating: t)), forward: forward, up: up, fovY: fovY)
        }
    }
}
