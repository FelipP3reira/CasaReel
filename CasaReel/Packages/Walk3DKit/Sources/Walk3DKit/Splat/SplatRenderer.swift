import CoreVideo
import Foundation
import Metal
import simd

/// Draws a Gaussian-splat scene from a camera pose into a BGRA pixel buffer.
///
/// Classic 3D Gaussian Splatting rasterization: each Gaussian's 3D covariance is projected to a 2D ellipse
/// in the vertex shader (EWA splatting), drawn as an instanced quad, and blended back to front.
/// Sorting happens on the CPU once per frame with a 16-bit counting sort, which is fast enough for an
/// offline video render. Colors use only the SH degree 0 term to keep on-device rendering efficient.
final class SplatRenderer {
    enum Failure: Error, Equatable {
        case noMetal
        case pipeline
        case render
    }

    /// Matches `Uniforms` in the shader (each `SIMD3<Float>` occupies 16 bytes, like `float3`).
    private struct Uniforms {
        var position: SIMD3<Float>
        var right: SIMD3<Float>
        var down: SIMD3<Float>
        var forward: SIMD3<Float>
        var focal: SIMD2<Float>
        var viewport: SIMD2<Float>
    }

    static let background = MTLClearColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)

    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLRenderPipelineState
    private let splatBuffer: any MTLBuffer
    private let orderBuffer: any MTLBuffer
    private let positions: [SIMD3<Float>]
    private var textureCache: CVMetalTextureCache?
    private var depths: [Float]
    private var buckets: [UInt16]
    private var counts = [UInt32](repeating: 0, count: 65_536)
    private var visibleCount = 0

    init(scene: SplatScene) throws(Failure) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw .noMetal }
        self.device = device
        self.queue = queue
        let library: any MTLLibrary
        do {
            library = try device.makeLibrary(source: SplatShaders.source, options: nil)
        } catch {
            throw .pipeline
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "splatVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "splatFragment")
        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = .bgra8Unorm
        // Premultiplied "over", drawn back to front.
        attachment?.isBlendingEnabled = true
        attachment?.sourceRGBBlendFactor = .one
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw .pipeline
        }
        let splats = scene.splats
        let splatBuffer = splats.withUnsafeBytes { bytes in
            bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared) }
        }
        guard let splatBuffer,
              let orderBuffer = device.makeBuffer(length: splats.count * MemoryLayout<UInt32>.stride, options: .storageModeShared)
        else { throw .noMetal }
        self.splatBuffer = splatBuffer
        self.orderBuffer = orderBuffer
        positions = splats.map { SIMD3($0.position.0, $0.position.1, $0.position.2) }
        depths = [Float](repeating: 0, count: splats.count)
        buckets = [UInt16](repeating: 0, count: splats.count)
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    /// - Parameter resort: `false` reuses the previous frame's order. Between close camera poses the
    ///   order barely changes, so a video can re-sort every few frames and look the same.
    func render(_ pose: CameraPose, into pixelBuffer: CVPixelBuffer, resort: Bool = true) throws(Failure) {
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
        guard let textureCache else { throw .render }
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTexture)
        guard let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { throw .render }

        let axes = Self.axes(for: pose)
        if resort { visibleCount = sortBackToFront(eye: pose.position, forward: axes.forward) }
        let visible = visibleCount
        let focalLength = Float(height) / 2 / tan(pose.fovY / 2)
        var uniforms = Uniforms(position: pose.position, right: axes.right, down: axes.down, forward: axes.forward,
                                focal: SIMD2(focalLength, focalLength), viewport: SIMD2(Float(width), Float(height)))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = Self.background
        pass.colorAttachments[0].storeAction = .store
        guard let commands = queue.makeCommandBuffer(), let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { throw .render }
        if visible > 0 {
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(splatBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(orderBuffer, offset: 0, index: 1)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: visible)
        }
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.status == .completed else { throw .render }
    }

    /// Camera axes (x right, y down, z forward), robust to a forward vector parallel to `up`.
    static func axes(for pose: CameraPose) -> (right: SIMD3<Float>, down: SIMD3<Float>, forward: SIMD3<Float>) {
        let forward = simd_normalize(pose.forward)
        var right = simd_cross(forward, pose.up)
        if simd_length(right) < 1e-4 { right = simd_cross(forward, abs(forward.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(1, 0, 0)) }
        right = simd_normalize(right)
        return (right, simd_cross(forward, right), forward)
    }

    /// Writes the indices of the Gaussians in front of the camera, farthest first, and returns how many.
    /// Runs every frame over millions of Gaussians, so it works on raw buffers: array accesses through
    /// class properties pay bounds, uniqueness and exclusivity checks on every element.
    func sortBackToFront(eye: SIMD3<Float>, forward: SIMD3<Float>) -> Int {
        let count = positions.count
        let order = orderBuffer.contents().bindMemory(to: UInt32.self, capacity: count)
        return positions.withUnsafeBufferPointer { positions in
            depths.withUnsafeMutableBufferPointer { depths in
                buckets.withUnsafeMutableBufferPointer { buckets in
                    counts.withUnsafeMutableBufferPointer { counts in
                        Self.countingSort(positions: positions, eye: eye, forward: forward,
                                          depths: depths, buckets: buckets, counts: counts, order: order)
                    }
                }
            }
        }
    }

    private static func countingSort(
        positions: UnsafeBufferPointer<SIMD3<Float>>, eye: SIMD3<Float>, forward: SIMD3<Float>,
        depths: UnsafeMutableBufferPointer<Float>, buckets: UnsafeMutableBufferPointer<UInt16>,
        counts: UnsafeMutableBufferPointer<UInt32>, order: UnsafeMutablePointer<UInt32>
    ) -> Int {
        let nearPlane: Float = 0.05
        var minDepth = Float.greatestFiniteMagnitude, maxDepth = -Float.greatestFiniteMagnitude
        for index in 0..<positions.count {
            let depth = simd_dot(positions[index] - eye, forward)
            depths[index] = depth
            if depth > nearPlane {
                minDepth = min(minDepth, depth)
                maxDepth = max(maxDepth, depth)
            }
        }
        guard minDepth <= maxDepth else { return 0 }
        let scale = maxDepth > minDepth ? 65_535 / (maxDepth - minDepth) : 0
        counts.update(repeating: 0)
        var visible = 0
        for index in 0..<positions.count where depths[index] > nearPlane {
            // Far → bucket 0, so a plain ascending counting sort gives back-to-front order.
            let bucket = UInt16(min(max((maxDepth - depths[index]) * scale, 0), 65_535))
            buckets[index] = bucket
            counts[Int(bucket)] += 1
            visible += 1
        }
        var running: UInt32 = 0
        for index in 0..<counts.count {
            let value = counts[index]
            counts[index] = running
            running += value
        }
        for index in 0..<positions.count where depths[index] > nearPlane {
            let bucket = Int(buckets[index])
            order[Int(counts[bucket])] = UInt32(index)
            counts[bucket] += 1
        }
        return visible
    }
}

enum SplatShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Splat {
        packed_float3 position;
        float covariance[6];
        uint color;
    };

    struct Uniforms {
        float3 position;
        float3 right;
        float3 down;
        float3 forward;
        float2 focal;
        float2 viewport;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 local;
        float4 color;
    };

    vertex VertexOut splatVertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                                 const device Splat *splats [[buffer(0)]],
                                 const device uint *order [[buffer(1)]],
                                 constant Uniforms &u [[buffer(2)]]) {
        VertexOut out;
        out.position = float4(0, 0, 2, 1);  // outside the clip volume: dropped
        out.local = float2(0);
        out.color = float4(0);
        Splat s = splats[order[instanceID]];
        float3 d = float3(s.position) - u.position;
        float3 c = float3(dot(d, u.right), dot(d, u.down), dot(d, u.forward));
        if (c.z < 0.05) { return out; }

        float3x3 sigma = float3x3(float3(s.covariance[0], s.covariance[1], s.covariance[2]),
                                  float3(s.covariance[1], s.covariance[3], s.covariance[4]),
                                  float3(s.covariance[2], s.covariance[4], s.covariance[5]));
        float3x3 view = transpose(float3x3(u.right, u.down, u.forward));
        float3x3 jacobian = float3x3(float3(u.focal.x / c.z, 0, 0),
                                     float3(0, u.focal.y / c.z, 0),
                                     float3(-u.focal.x * c.x / (c.z * c.z), -u.focal.y * c.y / (c.z * c.z), 0));
        float3x3 t = jacobian * view;
        float3x3 projected = t * sigma * transpose(t);
        float a = projected[0][0] + 0.3;
        float b = projected[0][1];
        float cc = projected[1][1] + 0.3;

        float mid = 0.5 * (a + cc);
        float radius = length(float2(0.5 * (a - cc), b));
        float lambda1 = mid + radius;
        float lambda2 = max(mid - radius, 0.1);
        float2 axis = abs(b) < 1e-6 ? (a >= cc ? float2(1, 0) : float2(0, 1)) : normalize(float2(b, lambda1 - a));
        // The scene writer already clamps scale. This second bound protects playback of an
        // interrupted or older scene file from a single screen-filling Gaussian.
        float2 major = min(sqrt(2.0 * lambda1), 160.0) * axis;
        float2 minor = min(sqrt(2.0 * lambda2), 160.0) * float2(axis.y, -axis.x);

        float2 center = u.focal * c.xy / c.z + 0.5 * u.viewport;
        float2 margin = 0.3 * u.viewport;
        if (any(center < -margin) || any(center > u.viewport + margin)) { return out; }

        float2 corner = float2((vertexID & 1) ? 2.0 : -2.0, (vertexID & 2) ? 2.0 : -2.0);
        float2 pixel = center + corner.x * major + corner.y * minor;
        out.position = float4(pixel.x / u.viewport.x * 2.0 - 1.0, 1.0 - pixel.y / u.viewport.y * 2.0, 0, 1);
        out.local = corner;
        out.color = float4(float(s.color & 0xff), float((s.color >> 8) & 0xff),
                           float((s.color >> 16) & 0xff), float((s.color >> 24) & 0xff)) / 255.0;
        return out;
    }

    fragment float4 splatFragment(VertexOut in [[stage_in]]) {
        float power = -dot(in.local, in.local);
        if (power < -4.0) { discard_fragment(); }
        float alpha = min(exp(power) * in.color.a, 0.99);
        return float4(in.color.rgb * alpha, alpha);
    }
    """
}
