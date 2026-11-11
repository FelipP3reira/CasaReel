import AVFoundation
import CoreVideo
import Foundation
import Metal
import simd

@main
enum CasaReelWalk3DRenderer {
    static func main() async {
        do {
            let arguments = try Arguments(CommandLine.arguments)
            let splats = try BrushPLY(url: arguments.input).splats(limit: 120_000)
            let poses = try CameraPath(url: arguments.dataset.appending(path: "transforms.json")).walk(frameCount: 360)
            try await VideoRenderer(splats: splats, poses: poses).write(to: arguments.video)
        } catch {
            FileHandle.standardError.write(Data("CasaReel renderer: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }
}

private struct Arguments {
    let dataset: URL
    let input: URL
    let video: URL

    init(_ values: [String]) throws {
        func value(_ name: String) throws -> URL {
            guard let index = values.firstIndex(of: name), values.indices.contains(index + 1) else {
                throw RenderError.usage
            }
            return URL(fileURLWithPath: values[index + 1])
        }
        dataset = try value("--dataset")
        input = try value("--input")
        video = try value("--video")
    }
}

private enum RenderError: LocalizedError {
    case usage, invalidPLY, unsupportedPLY, invalidPath, metal, writer

    var errorDescription: String? {
        switch self {
        case .usage: "usage: casareel-walk3d-renderer --dataset <nerfstudio-dir> --input <scene.ply> --video <out.mp4>"
        case .invalidPLY: "invalid Brush PLY"
        case .unsupportedPLY: "the Brush PLY must be binary little-endian"
        case .invalidPath: "invalid Nerfstudio transforms.json"
        case .metal: "Metal renderer unavailable"
        case .writer: "could not write MP4"
        }
    }
}

// Brush exports standard binary Gaussian PLY. The header is parsed rather than assumed so that
// property order changes do not silently create a corrupted video.
private struct BrushPLY {
    private struct Field { let name: String; let offset: Int; let bytes: Int; let type: String }
    private let data: Data
    private let recordStart: Int
    private let recordSize: Int
    private let count: Int
    private let fields: [String: Field]

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let marker = data.range(of: Data("end_header\n".utf8)) else { throw RenderError.invalidPLY }
        recordStart = marker.upperBound
        let header = String(decoding: data[..<recordStart], as: UTF8.self)
        guard header.contains("format binary_little_endian") else { throw RenderError.unsupportedPLY }
        var vertexCount: Int?
        var offset = 0
        var output: [String: Field] = [:]
        var inVertex = false
        for line in header.split(separator: "\n") {
            let words = line.split(separator: " ").map(String.init)
            if words.count >= 3, words[0] == "element" {
                inVertex = words[1] == "vertex"
                if inVertex { vertexCount = Int(words[2]) }
            } else if inVertex, words.count == 3, words[0] == "property" {
                let bytes = Self.bytes(for: words[1])
                guard bytes > 0 else { throw RenderError.invalidPLY }
                output[words[2]] = Field(name: words[2], offset: offset, bytes: bytes, type: words[1])
                offset += bytes
            }
        }
        guard let vertexCount, vertexCount > 0, offset > 0,
              recordStart + vertexCount * offset <= data.count else { throw RenderError.invalidPLY }
        count = vertexCount
        recordSize = offset
        fields = output
        for required in ["x", "y", "z", "f_dc_0", "f_dc_1", "f_dc_2", "opacity", "scale_0", "scale_1", "scale_2"] where fields[required] == nil {
            throw RenderError.invalidPLY
        }
    }

    func splats(limit: Int) throws -> [GPUSplat] {
        let sampleStep = max(1, count / max(limit, 1))
        var output: [GPUSplat] = []
        output.reserveCapacity(min(count, limit))
        for index in Swift.stride(from: 0, to: count, by: sampleStep) {
            let base = recordStart + index * recordSize
            let position = SIMD3(value("x", base), value("y", base), value("z", base))
            let rawScale = SIMD3(value("scale_0", base), value("scale_1", base), value("scale_2", base))
            let dc = SIMD3(value("f_dc_0", base), value("f_dc_1", base), value("f_dc_2", base))
            guard finite(position), finite(rawScale), finite(dc) else { continue }
            // Brush stores log-scales and a unit quaternion. Keeping all three
            // axes is essential: a Gaussian is an oriented ellipsoid, not a
            // circular point sprite.
            let scale = simd_clamp(SIMD3(exp(rawScale.x), exp(rawScale.y), exp(rawScale.z)), SIMD3(repeating: 0.001), SIMD3(repeating: 0.35))
            let rawRotation = SIMD4(value("rot_0", base), value("rot_1", base), value("rot_2", base), value("rot_3", base))
            let hasRotation = rawRotation.x.isFinite && rawRotation.y.isFinite
                && rawRotation.z.isFinite && rawRotation.w.isFinite
            let rotation = hasRotation && simd_length(rawRotation) > 0.0001
                ? simd_normalize(rawRotation)
                : SIMD4(1, 0, 0, 0)
            let alpha = min(max(sigmoid(value("opacity", base)), 0.08), 0.98)
            let color = SIMD3(repeating: 0.5) + dc * 0.2820948
            output.append(GPUSplat(position: position, scale: scale, rotation: rotation, color: SIMD4(simd_clamp(color, SIMD3(repeating: 0), SIMD3(repeating: 1)), alpha)))
            if output.count == limit { break }
        }
        guard !output.isEmpty else { throw RenderError.invalidPLY }
        return output
    }

    private func value(_ name: String, _ base: Int) -> Float {
        guard let field = fields[name] else { return .nan }
        let address = base + field.offset
        switch field.type {
        case "float", "float32":
            return Float(bitPattern: data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: address, as: UInt32.self).littleEndian })
        case "double", "float64":
            return Float(Double(bitPattern: data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: address, as: UInt64.self).littleEndian }))
        default: return .nan
        }
    }

    private static func bytes(for type: String) -> Int {
        switch type { case "float", "float32", "int", "uint", "int32", "uint32": 4; case "double", "float64": 8; case "char", "uchar", "int8", "uint8": 1; case "short", "ushort", "int16", "uint16": 2; default: 0 }
    }
}

private struct GPUSplat {
    var position: SIMD3<Float>
    var scale: SIMD3<Float>
    /// Brush PLY uses the scalar-first quaternion order (w, x, y, z).
    var rotation: SIMD4<Float>
    var color: SIMD4<Float>
}

private struct Pose {
    var position: SIMD3<Float>
    var forward: SIMD3<Float>
    var up: SIMD3<Float>
    var fovY: Float
}

private struct CameraPath {
    private struct File: Decodable {
        struct Frame: Decodable { let transformMatrix: [[Float]] }
        let flY: Float
        let h: Float
        let frames: [Frame]
    }
    private let keyframes: [Pose]

    init(url: URL) throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let file = try decoder.decode(File.self, from: Data(contentsOf: url))
        let fovY = 2 * atan(file.h / (2 * file.flY))
        keyframes = file.frames.compactMap { frame -> Pose? in
            guard frame.transformMatrix.count == 4, frame.transformMatrix.allSatisfy({ $0.count == 4 }) else { return nil }
            let m = frame.transformMatrix
            let position = SIMD3(m[0][3], m[1][3], m[2][3])
            // Brush's exported splats use the capture's forward-facing +Z direction.
            // The dataset conversion has already changed the image coordinate axes, so
            // negating this column here makes every camera render away from the scene.
            let forward = SIMD3(m[0][2], m[1][2], m[2][2])
            let up = SIMD3(m[0][1], m[1][1], m[2][1])
            guard finite(position), simd_length(forward) > 0.5, simd_length(up) > 0.5 else { return nil }
            return Pose(position: position, forward: simd_normalize(forward), up: simd_normalize(up), fovY: fovY)
        }
        guard keyframes.count >= 2 else { throw RenderError.invalidPath }
    }

    func walk(frameCount: Int) -> [Pose] {
        let up = simd_normalize(keyframes.reduce(SIMD3<Float>()) { $0 + $1.up })
        var distances: [Float] = [0]
        for index in 1..<keyframes.count { distances.append(distances[index - 1] + simd_distance(keyframes[index].position, keyframes[index - 1].position)) }
        if distances.last ?? 0 < 0.001 { distances = keyframes.indices.map(Float.init) }
        let total = distances.last ?? 1
        var segment = 0
        return (0..<frameCount).map { frame in
            let target = total * Float(frame) / Float(max(frameCount - 1, 1))
            while segment < distances.count - 2, distances[segment + 1] < target { segment += 1 }
            let span = distances[segment + 1] - distances[segment]
            let t = span > 0 ? (target - distances[segment]) / span : 0
            let a = keyframes[segment], b = keyframes[segment + 1]
            return Pose(position: simd_mix(a.position, b.position, SIMD3(repeating: t)), forward: simd_normalize(simd_mix(a.forward, b.forward, SIMD3(repeating: t))), up: up, fovY: a.fovY)
        }
    }
}

private final class VideoRenderer {
    private struct Uniforms { var position, right, up, forward: SIMD3<Float>; var focal, viewport: SIMD2<Float> }
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    /// The source order in a PLY is arbitrary. Alpha-blended Gaussian splats
    /// must be submitted back-to-front for the active camera on every frame.
    private let sourceSplats: [GPUSplat]
    private let splats: MTLBuffer
    private let count: Int
    private let poses: [Pose]
    private var textureCache: CVMetalTextureCache?

    init(splats input: [GPUSplat], poses: [Pose]) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw RenderError.metal }
        self.device = device; self.queue = queue; sourceSplats = input; count = input.count; self.poses = poses
        guard let splats = input.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else { throw RenderError.metal }
        self.splats = splats
        let library = try device.makeLibrary(source: Self.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertexMain")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    func write(to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { throw RenderError.writer }
        let width = 720, height = 1280, fps = 24
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 5_000_000]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferMetalCompatibilityKey as String: true, kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        guard writer.canAdd(input) else { throw RenderError.writer }
        writer.add(input)
        guard writer.startWriting() else { throw RenderError.writer }
        writer.startSession(atSourceTime: .zero)
        do {
            for (index, pose) in poses.enumerated() {
                while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
                guard let pool = adaptor.pixelBufferPool else { throw RenderError.writer }
                var buffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw RenderError.writer }
                try render(pose: pose, into: buffer)
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))) else { throw RenderError.writer }
            }
        } catch {
            writer.cancelWriting()
            throw error
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw RenderError.writer }
    }

    private func render(pose: Pose, into buffer: CVPixelBuffer) throws {
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard let textureCache else { throw RenderError.metal }
        var cvTexture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, buffer, nil, .bgra8Unorm, width, height, 0, &cvTexture) == kCVReturnSuccess,
              let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture),
              let commands = queue.makeCommandBuffer() else { throw RenderError.metal }
        var right = simd_cross(pose.forward, pose.up)
        guard simd_length(right) > 0.0001 else { throw RenderError.invalidPath }
        right = simd_normalize(right)
        let up = simd_normalize(simd_cross(right, pose.forward))
        // Rendering unsorted translucent splats gives undefined-looking
        // accumulation (walls smear over nearby objects). Brush exports no
        // painter order, so create the order for the current viewpoint here.
        let orderedSplats = sourceSplats.sorted {
            simd_dot($0.position - pose.position, pose.forward) > simd_dot($1.position - pose.position, pose.forward)
        }
        orderedSplats.withUnsafeBytes { bytes in
            guard let source = bytes.baseAddress else { return }
            splats.contents().copyMemory(from: source, byteCount: bytes.count)
        }
        let focal = Float(height) / (2 * tan(pose.fovY / 2))
        var uniforms = Uniforms(position: pose.position, right: right, up: up, forward: pose.forward, focal: SIMD2(repeating: focal), viewport: SIMD2(Float(width), Float(height)))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { throw RenderError.metal }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(splats, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        encoder.endEncoding()
        commands.commit(); commands.waitUntilCompleted()
        guard commands.status == .completed else { throw RenderError.metal }
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Splat { float3 position; float3 scale; float4 rotation; float4 color; };
    struct Uniforms { float3 position; float3 right; float3 up; float3 forward; float2 focal; float2 viewport; };
    struct Out { float4 position [[position]]; float2 local; float4 color; };
    vertex Out vertexMain(uint vertexID [[vertex_id]], uint instanceID [[instance_id]], const device Splat *splats [[buffer(0)]], constant Uniforms &u [[buffer(1)]]) {
      Out out; out.position=float4(2,2,2,1); out.local=float2(0); out.color=float4(0);
      Splat s=splats[instanceID]; float3 d=s.position-u.position; float3 p=float3(dot(d,u.right),dot(d,u.up),dot(d,u.forward)); if(p.z<0.05) return out;
      float2 center=float2(u.focal.x*p.x/p.z,u.focal.y*p.y/p.z)+0.5*u.viewport;
      // Project the three rotated Gaussian axes through the perspective
      // camera. Their weighted outer products form the 2D covariance.
      float4 q=s.rotation; float3 qv=q.yzw;
      float3 axes[3]={float3(1,0,0),float3(0,1,0),float3(0,0,1)};
      float a=0, b=0, c=0;
      for(uint i=0;i<3;i++) { float3 world=axes[i]+2.0*cross(qv,cross(qv,axes[i])+q.x*axes[i]); float3 v=float3(dot(world,u.right),dot(world,u.up),dot(world,u.forward)); float2 j=float2(u.focal.x*(v.x*p.z-p.x*v.z)/(p.z*p.z),u.focal.y*(v.y*p.z-p.y*v.z)/(p.z*p.z)); float w=s.scale[i]*s.scale[i]; a+=w*j.x*j.x; b+=w*j.x*j.y; c+=w*j.y*j.y; }
      float disc=sqrt(max(0.0,(a-c)*(a-c)+4.0*b*b)); float l1=max(0.25,0.5*(a+c+disc)); float l2=max(0.25,0.5*(a+c-disc)); float angle=0.5*atan2(2.0*b,a-c); float2 e1=float2(cos(angle),sin(angle)); float2 e2=float2(-e1.y,e1.x); float2 corner=float2((vertexID&1)?1:-1,(vertexID&2)?1:-1); float2 local=corner*3.0; float2 pixel=center+e1*(local.x*min(sqrt(l1),90.0))+e2*(local.y*min(sqrt(l2),90.0));
      out.position=float4(pixel.x/u.viewport.x*2-1,1-pixel.y/u.viewport.y*2,0,1); out.local=local; out.color=s.color; return out;
    }
    fragment float4 fragmentMain(Out in [[stage_in]]) { float r2=dot(in.local,in.local); if(r2>9) discard_fragment(); return float4(in.color.rgb, in.color.a*exp(-0.5*r2)); }
    """
}

private func sigmoid(_ value: Float) -> Float { 1 / (1 + exp(-value)) }
private func finite(_ value: SIMD3<Float>) -> Bool { value.x.isFinite && value.y.isFinite && value.z.isFinite }
