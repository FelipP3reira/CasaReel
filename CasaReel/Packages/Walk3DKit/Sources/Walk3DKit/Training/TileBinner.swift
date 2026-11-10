import Foundation

/// Sorts the projected Gaussians front to back and lists, per 16×16 tile, the ones that touch it.
///
/// Runs on the CPU between the GPU passes, over shared (unified) memory: a counting sort on quantized depth
/// and two passes over the tile rectangles. Scratch memory is allocated once and walked through raw
/// pointers: Swift arrays held by a class pay uniqueness and exclusivity checks on every element.
final class TileBinner {
    static let depthBuckets = 1 << 16

    private var capacity = 0
    private var visible: UnsafeMutablePointer<UInt32>
    private var order: UnsafeMutablePointer<UInt32>
    private var keys: UnsafeMutablePointer<UInt16>
    private let bucketStarts: UnsafeMutablePointer<Int>
    private var tileCapacity = 0
    private var cursor: UnsafeMutablePointer<UInt32>

    init() {
        visible = .allocate(capacity: 1)
        order = .allocate(capacity: 1)
        keys = .allocate(capacity: 1)
        bucketStarts = .allocate(capacity: Self.depthBuckets + 1)
        cursor = .allocate(capacity: 1)
    }

    deinit {
        visible.deallocate()
        order.deallocate()
        keys.deallocate()
        bucketStarts.deallocate()
        cursor.deallocate()
    }

    /// - Parameters:
    ///   - rects: per Gaussian, tile rectangle (minX, minY, maxX, maxY); empty = culled.
    ///   - depths: per Gaussian, camera-space depth (read with `depthStride` floats between entries).
    ///   - ranges: output, (start, end) into `list` per tile.
    ///   - list: output, Gaussian indices; Gaussians past `capacity` instances are dropped, farthest first.
    /// - Returns: the number of instances written.
    @discardableResult
    func bin(count: Int, rects: UnsafePointer<SIMD4<UInt32>>, depths: UnsafePointer<Float>, depthStride: Int,
             tilesX: Int, tileCount: Int, ranges: UnsafeMutablePointer<SIMD2<UInt32>>,
             list: UnsafeMutablePointer<UInt32>, capacity listCapacity: Int) -> Int {
        reserve(gaussians: count, tiles: tileCount)
        let sorted = sortVisible(count: count, rects: rects, depths: depths, depthStride: depthStride)
        cursor.initialize(repeating: 0, count: tileCount)
        // Counts per tile, stopping at the first Gaussian that would overflow the list.
        var total = 0, kept = 0
        while kept < sorted {
            let r = rects[Int(order[kept])]
            let area = Int((r.z - r.x) * (r.w - r.y))
            guard total + area <= listCapacity else { break }
            total += area
            kept += 1
            for ty in Int(r.y)..<Int(r.w) {
                for tx in Int(r.x)..<Int(r.z) { cursor[ty * tilesX + tx] += 1 }
            }
        }
        var start: UInt32 = 0
        for tile in 0..<tileCount {
            let n = cursor[tile]
            ranges[tile] = SIMD2(start, start + n)
            cursor[tile] = start
            start += n
        }
        for slot in 0..<kept {
            let id = order[slot]
            let r = rects[Int(id)]
            for ty in Int(r.y)..<Int(r.w) {
                for tx in Int(r.x)..<Int(r.z) {
                    let tile = ty * tilesX + tx
                    list[Int(cursor[tile])] = id
                    cursor[tile] += 1
                }
            }
        }
        return total
    }

    private func reserve(gaussians: Int, tiles: Int) {
        if gaussians > capacity {
            visible.deallocate()
            order.deallocate()
            keys.deallocate()
            visible = .allocate(capacity: gaussians)
            order = .allocate(capacity: gaussians)
            keys = .allocate(capacity: gaussians)
            capacity = gaussians
        }
        if tiles > tileCapacity {
            cursor.deallocate()
            cursor = .allocate(capacity: tiles)
            tileCapacity = tiles
        }
    }

    /// Writes the visible Gaussians (non-empty rectangle) to `order`, nearest first, and returns how many.
    private func sortVisible(count: Int, rects: UnsafePointer<SIMD4<UInt32>>, depths: UnsafePointer<Float>, depthStride: Int) -> Int {
        var n = 0
        var near = Float.greatestFiniteMagnitude, far: Float = 0
        for id in 0..<count {
            let r = rects[id]
            guard r.z > r.x, r.w > r.y else { continue }
            let depth = depths[id * depthStride]
            near = min(near, depth)
            far = max(far, depth)
            visible[n] = UInt32(id)
            n += 1
        }
        let scale = far > near ? Float(Self.depthBuckets - 1) / (far - near) : 0
        bucketStarts.initialize(repeating: 0, count: Self.depthBuckets + 1)
        for slot in 0..<n {
            let depth = depths[Int(visible[slot]) * depthStride]
            let key = UInt16(min(max((depth - near) * scale, 0), Float(Self.depthBuckets - 1)))
            keys[slot] = key
            bucketStarts[Int(key) + 1] += 1
        }
        for bucket in 0..<Self.depthBuckets { bucketStarts[bucket + 1] += bucketStarts[bucket] }
        for slot in 0..<n {
            let key = Int(keys[slot])
            order[bucketStarts[key]] = visible[slot]
            bucketStarts[key] += 1
        }
        return n
    }
}
