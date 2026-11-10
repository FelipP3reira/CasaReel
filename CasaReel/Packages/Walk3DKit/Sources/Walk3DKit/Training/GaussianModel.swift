import Foundation
import simd

/// The trainable Gaussians on the CPU side: initialization, densification and export.
/// Layout per Gaussian matches `TrainingShaders` (16 floats).
struct GaussianModel {
    static let stride = 16
    static let minInitialCount = 5_000

    var params: [Float]
    var m: [Float]
    var v: [Float]

    var count: Int { params.count / Self.stride }

    init(params: [Float]) {
        self.params = params
        m = [Float](repeating: 0, count: params.count)
        v = [Float](repeating: 0, count: params.count)
    }

    static func logit(_ value: Float) -> Float {
        let clamped = min(max(value, 0.001), 0.999)
        return log(clamped / (1 - clamped))
    }

    static func sigmoid(_ value: Float) -> Float { 1 / (1 + exp(-value)) }

    static func gaussian(position: SIMD3<Float>, logScale: SIMD3<Float>, rotation: SIMD4<Float> = SIMD4(1, 0, 0, 0),
                         color: SIMD3<Float>, opacity: Float) -> [Float] {
        [position.x, position.y, position.z, logScale.x, logScale.y, logScale.z,
         rotation.x, rotation.y, rotation.z, rotation.w,
         logit(color.x), logit(color.y), logit(color.z), logit(opacity), 0, 0]
    }

    func position(_ index: Int) -> SIMD3<Float> {
        let base = index * Self.stride
        return SIMD3(params[base], params[base + 1], params[base + 2])
    }

    func scale(_ index: Int) -> SIMD3<Float> {
        let base = index * Self.stride
        return exp(SIMD3(params[base + 3], params[base + 4], params[base + 5]))
    }

    func opacity(_ index: Int) -> Float { Self.sigmoid(params[index * Self.stride + 13]) }

    // MARK: - Initialization

    /// One Gaussian per ARKit feature point, colored from the keyframes that see it and sized from its
    /// neighbors. Sparse captures are topped up with random Gaussians inside the scene's bounds.
    static func initial<G: RandomNumberGenerator>(points: [SIMD3<Float>], views: [TrainingView], images: [TrainingImage],
                                                  extent: Float, generator: inout G) -> GaussianModel {
        let colors = sampleColors(points: points, views: views, images: images)
        let spacing = neighborSpacing(points, fallback: extent / 100)
        var params: [Float] = []
        params.reserveCapacity(max(points.count, minInitialCount) * stride)
        for (index, point) in points.enumerated() {
            let size = min(max(spacing[index], 0.002), 0.5)
            params += gaussian(position: point, logScale: SIMD3(repeating: log(size)), color: colors[index], opacity: 0.1)
        }
        let bounds = sceneBounds(points: points, views: views)
        let fillSize = log(max(extent / 50, 0.01))
        for _ in points.count..<max(points.count, minInitialCount) {
            let position = SIMD3(Float.random(in: bounds.min.x...bounds.max.x, using: &generator),
                                 Float.random(in: bounds.min.y...bounds.max.y, using: &generator),
                                 Float.random(in: bounds.min.z...bounds.max.z, using: &generator))
            params += gaussian(position: position, logScale: SIMD3(repeating: fillSize), color: SIMD3(repeating: 0.5), opacity: 0.1)
        }
        return GaussianModel(params: params)
    }

    /// Average color of each point over (a subset of) the keyframes it projects into. Occlusion is ignored:
    /// training fixes the few wrong colors this gives.
    static func sampleColors(points: [SIMD3<Float>], views: [TrainingView], images: [TrainingImage]) -> [SIMD3<Float>] {
        var sums = [SIMD4<Float>](repeating: .zero, count: points.count)
        let step = max(1, views.count / 60)
        for viewIndex in Swift.stride(from: 0, to: views.count, by: step) {
            let view = views[viewIndex], image = images[viewIndex]
            for (index, point) in points.enumerated() {
                guard let pixel = view.project(point), let color = image.color(at: pixel) else { continue }
                sums[index] += SIMD4(color, 1)
            }
        }
        return sums.map { $0.w > 0 ? SIMD3($0.x, $0.y, $0.z) / $0.w : SIMD3(repeating: 0.5) }
    }

    /// Mean distance to the 3 nearest neighbors, searched in a hash grid (27 cells around each point).
    static func neighborSpacing(_ points: [SIMD3<Float>], fallback: Float) -> [Float] {
        guard points.count > 3 else { return [Float](repeating: fallback, count: points.count) }
        let cell = max(fallback, 1e-3)
        func key(_ p: SIMD3<Float>) -> SIMD3<Int32> { SIMD3<Int32>(Int32(floor(p.x / cell)), Int32(floor(p.y / cell)), Int32(floor(p.z / cell))) }
        var grid: [SIMD3<Int32>: [Int32]] = [:]
        for (index, point) in points.enumerated() { grid[key(point), default: []].append(Int32(index)) }
        return points.enumerated().map { index, point in
            let center = key(point)
            var nearest: [Float] = []
            for dx in Int32(-1)...1 {
                for dy in Int32(-1)...1 {
                    for dz in Int32(-1)...1 {
                        for other in grid[center &+ SIMD3(dx, dy, dz)] ?? [] where Int(other) != index {
                            nearest.append(simd_distance(point, points[Int(other)]))
                        }
                    }
                }
            }
            guard !nearest.isEmpty else { return fallback }
            let closest = nearest.sorted().prefix(3)
            return closest.reduce(0, +) / Float(closest.count)
        }
    }

    static func sceneBounds(points: [SIMD3<Float>], views: [TrainingView]) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        let all = points + views.map(\.center)
        guard var low = all.first else { return (SIMD3(repeating: -1), SIMD3(repeating: 1)) }
        var high = low
        for point in all {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        return (low - 0.1, high + 0.1)
    }

    /// Radius of the camera positions around their mean, as in the paper; positions learn at a rate scaled by it.
    static func extent(of views: [TrainingView]) -> Float {
        guard !views.isEmpty else { return 1 }
        let mean = views.reduce(SIMD3<Float>()) { $0 + $1.center } / Float(views.count)
        let radius = views.map { simd_distance($0.center, mean) }.max() ?? 1
        return max(radius * 1.1, 0.5)
    }

    // MARK: - Densification

    struct DensifyRule {
        var gradientThreshold: Float = 0.0002
        var minOpacity: Float = 0.005
        /// Fraction of the extent separating "small" (cloned) from "large" (split) Gaussians.
        var splitScale: Float = 0.01
        /// Fraction of the extent above which a Gaussian is pruned as too big (after the first opacity reset).
        var maxScale: Float = 0.1
        var pruneLarge = false
        var maxCount = 300_000
    }

    /// Clones small Gaussians and splits large ones where the view-space gradient is high, then prunes
    /// transparent (and, later on, huge) ones. `stats` holds (gradient sum, times seen) per Gaussian.
    mutating func densify<G: RandomNumberGenerator>(stats: [SIMD2<Float>], extent: Float, rule: DensifyRule, generator: inout G) {
        let stride = Self.stride
        var candidates: [(index: Int, gradient: Float)] = []
        for index in 0..<count where stats[index].y > 0 {
            let gradient = stats[index].x / stats[index].y
            if gradient >= rule.gradientThreshold { candidates.append((index, gradient)) }
        }
        // Splits add one net Gaussian, clones one: keep the strongest within the budget.
        let budget = max(0, rule.maxCount - count)
        if candidates.count > budget {
            candidates.sort { $0.gradient > $1.gradient }
            candidates.removeLast(candidates.count - budget)
        }
        var remove = [Bool](repeating: false, count: count)
        var added: [Float] = []
        for (index, _) in candidates {
            let base = index * stride
            let original = Array(params[base..<(base + stride)])
            let scale = self.scale(index)
            if scale.max() <= rule.splitScale * extent {
                added += original
                continue
            }
            let q = simd_quatf(ix: original[7], iy: original[8], iz: original[9], r: original[6]).normalized
            for _ in 0..<2 {
                let noise = SIMD3(Float.normal(using: &generator), Float.normal(using: &generator), Float.normal(using: &generator))
                let offset = q.act(noise * scale)
                var copy = original
                copy[0] += offset.x; copy[1] += offset.y; copy[2] += offset.z
                for axis in 3...5 { copy[axis] -= log(1.6) }
                added += copy
            }
            remove[index] = true
        }
        for index in 0..<count where !remove[index] {
            if opacity(index) < rule.minOpacity || (rule.pruneLarge && scale(index).max() > rule.maxScale * extent) {
                remove[index] = true
            }
        }
        var newParams: [Float] = [], newM: [Float] = [], newV: [Float] = []
        newParams.reserveCapacity(params.count + added.count)
        newM.reserveCapacity(params.count + added.count)
        newV.reserveCapacity(params.count + added.count)
        for index in 0..<count where !remove[index] {
            let range = (index * stride)..<((index + 1) * stride)
            newParams += params[range]
            newM += m[range]
            newV += v[range]
        }
        newParams += added
        newM += [Float](repeating: 0, count: added.count)
        newV += [Float](repeating: 0, count: added.count)
        params = newParams
        m = newM
        v = newV
    }

    /// Caps every opacity low so floaters must prove themselves again (and get pruned if they don't).
    mutating func resetOpacity(to ceiling: Float = 0.01) {
        let limit = Self.logit(ceiling)
        for index in 0..<count {
            let slot = index * Self.stride + 13
            params[slot] = min(params[slot], limit)
            m[slot] = 0
            v[slot] = 0
        }
    }

    // MARK: - Export

    /// The 32-byte records `SplatScene` reads; nearly invisible Gaussians are dropped.
    func splatData(minOpacity: Float = 0.02) -> Data {
        var data = Data(capacity: count * SplatScene.recordSize)
        for index in 0..<count {
            let base = index * Self.stride
            let opacity = self.opacity(index)
            let position = self.position(index), scale = self.scale(index)
            guard opacity >= minOpacity, position.allFinite, scale.allFinite else { continue }
            for value in [position.x, position.y, position.z, scale.x, scale.y, scale.z] {
                withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            }
            func byte(_ value: Float) -> UInt8 { UInt8(min(max((value * 255).rounded(), 0), 255)) }
            data.append(contentsOf: [byte(Self.sigmoid(params[base + 10])), byte(Self.sigmoid(params[base + 11])),
                                     byte(Self.sigmoid(params[base + 12])), byte(opacity)])
            var q = SIMD4(params[base + 6], params[base + 7], params[base + 8], params[base + 9])
            let length = simd_length(q)
            q = length > 0 ? q / length : SIMD4(1, 0, 0, 0)
            for component in [q.x, q.y, q.z, q.w] {
                data.append(UInt8(min(max((component * 128 + 128).rounded(), 0), 255)))
            }
        }
        return data
    }
}

extension Float {
    /// Standard normal sample (Box–Muller).
    static func normal<G: RandomNumberGenerator>(using generator: inout G) -> Float {
        let u1 = Float.random(in: Float.ulpOfOne..<1, using: &generator)
        let u2 = Float.random(in: 0..<1, using: &generator)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

/// SplitMix64: a seeded generator, so a training run (and its tests) can be reproduced.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
