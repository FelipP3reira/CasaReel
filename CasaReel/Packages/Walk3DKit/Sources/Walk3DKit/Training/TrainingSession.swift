import Foundation
import Metal
import simd

/// The GPU side of training: buffers, pipelines and one optimization step.
final class TrainingSession {
    enum Failure: Error {
        case noMetal
        /// A command buffer did not complete (the app went to the background, or the GPU reset).
        case gpu
    }

    /// Layout of `Step` in `TrainingShaders`.
    struct Step {
        /// position, scale, rotation, color.
        var lrA: SIMD4<Float>
        /// opacity, 1 − β1^t, 1 − β2^t, apply (0 = gradients only).
        var lrB: SIMD4<Float>
        var counts: SIMD4<UInt32>
    }

    static let screenStride = 12
    static let projectedFloats = 12

    let views: [TrainingView]
    private(set) var count: Int
    let capacity: Int
    let listCapacity: Int

    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let preprocess: any MTLComputePipelineState
    private let forward: any MTLComputePipelineState
    private let backward: any MTLComputePipelineState
    private let backwardStep: any MTLComputePipelineState
    private let params: any MTLBuffer
    private let m: any MTLBuffer
    private let v: any MTLBuffer
    private let grads: any MTLBuffer
    private let projected: any MTLBuffer
    private let rects: any MTLBuffer
    private let screenGrads: any MTLBuffer
    private let densifyStats: any MTLBuffer
    private let ranges: any MTLBuffer
    private let list: any MTLBuffer
    private let pixelState: any MTLBuffer
    private let pixelLast: any MTLBuffer
    private let pixelLoss: any MTLBuffer
    private let targets: any MTLTexture
    private let binner = TileBinner()

    /// All images must share one size (ARKit keeps one video format for a session).
    init(model: GaussianModel, views: [TrainingView], images: [TrainingImage], capacity: Int, listCapacity: Int = 6_000_000) throws(Failure) {
        guard let first = views.first, images.count == views.count,
              let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw .noMetal }
        self.views = views
        self.device = device
        self.queue = queue
        self.capacity = max(capacity, model.count)
        self.listCapacity = listCapacity
        count = model.count
        do {
            let library = try device.makeLibrary(source: TrainingShaders.source, options: nil)
            func pipeline(_ name: String) throws -> any MTLComputePipelineState {
                guard let function = library.makeFunction(name: name) else { throw Failure.noMetal }
                return try device.makeComputePipelineState(function: function)
            }
            preprocess = try pipeline("preprocess")
            forward = try pipeline("rasterizeForward")
            backward = try pipeline("rasterizeBackward")
            backwardStep = try pipeline("backwardStep")
        } catch {
            throw .noMetal
        }
        let floats = self.capacity * GaussianModel.stride * MemoryLayout<Float>.stride
        let pixels = first.width * first.height
        func buffer(_ length: Int) throws(Failure) -> any MTLBuffer {
            guard let buffer = device.makeBuffer(length: max(length, 16), options: .storageModeShared) else { throw .noMetal }
            return buffer
        }
        params = try buffer(floats)
        m = try buffer(floats)
        v = try buffer(floats)
        grads = try buffer(floats)
        projected = try buffer(self.capacity * Self.projectedFloats * MemoryLayout<Float>.stride)
        rects = try buffer(self.capacity * MemoryLayout<SIMD4<UInt32>>.stride)
        screenGrads = try buffer(self.capacity * Self.screenStride * MemoryLayout<Float>.stride)
        densifyStats = try buffer(self.capacity * MemoryLayout<SIMD2<Float>>.stride)
        ranges = try buffer(first.tileCount * MemoryLayout<SIMD2<UInt32>>.stride)
        list = try buffer(listCapacity * MemoryLayout<UInt32>.stride)
        pixelState = try buffer(pixels * MemoryLayout<SIMD4<Float>>.stride)
        pixelLast = try buffer(pixels * MemoryLayout<UInt32>.stride)
        pixelLoss = try buffer(pixels * MemoryLayout<Float>.stride)

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.width = first.width
        descriptor.height = first.height
        descriptor.arrayLength = images.count
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let targets = device.makeTexture(descriptor: descriptor) else { throw .noMetal }
        for (slice, image) in images.enumerated() {
            guard image.width == first.width, image.height == first.height else { throw .noMetal }
            image.pixels.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                targets.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0, slice: slice,
                                withBytes: base, bytesPerRow: image.width * 4, bytesPerImage: image.width * image.height * 4)
            }
        }
        self.targets = targets
        upload(model)
    }

    // MARK: - Model transfer (CPU ⇄ GPU)

    func upload(_ model: GaussianModel) {
        count = min(model.count, capacity)
        let length = count * GaussianModel.stride
        model.params.withUnsafeBufferPointer { copy($0, into: params, count: length) }
        model.m.withUnsafeBufferPointer { copy($0, into: m, count: length) }
        model.v.withUnsafeBufferPointer { copy($0, into: v, count: length) }
        memset(densifyStats.contents(), 0, capacity * MemoryLayout<SIMD2<Float>>.stride)
    }

    func download() -> GaussianModel {
        let length = count * GaussianModel.stride
        var model = GaussianModel(params: read(params, count: length))
        model.m = read(m, count: length)
        model.v = read(v, count: length)
        return model
    }

    func densifyStatistics() -> [SIMD2<Float>] {
        let pointer = densifyStats.contents().bindMemory(to: SIMD2<Float>.self, capacity: capacity)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    /// Parameter gradients of the last step (for tests).
    func gradients() -> [Float] { read(grads, count: count * GaussianModel.stride) }

    /// L1 loss of the last step: mean over pixels and channels.
    func loss() -> Float {
        guard let view = views.first else { return 0 }
        let pixels = view.width * view.height
        let pointer = pixelLoss.contents().bindMemory(to: Float.self, capacity: pixels)
        var sum: Float = 0
        for index in 0..<pixels { sum += pointer[index] }
        return sum * view.background.w
    }

    // MARK: - One step

    /// Renders view `viewIndex`, backpropagates the L1 loss and, when `step.lrB.w` is non-zero, updates the parameters.
    func run(viewIndex: Int, step: Step) throws(Failure) {
        var view = views[viewIndex]
        var count32 = UInt32(count)
        var step = step
        step.counts = SIMD4(count32, 0, 0, 0)
        guard count > 0 else { return }

        guard let first = queue.makeCommandBuffer(), let encoder = first.makeComputeCommandEncoder() else { throw .gpu }
        encoder.setComputePipelineState(preprocess)
        encoder.setBuffer(params, offset: 0, index: 0)
        encoder.setBuffer(projected, offset: 0, index: 1)
        encoder.setBuffer(rects, offset: 0, index: 2)
        encoder.setBytes(&view, length: MemoryLayout<TrainingView>.stride, index: 3)
        encoder.setBytes(&count32, length: MemoryLayout<UInt32>.stride, index: 4)
        dispatch(encoder, pipeline: preprocess, threads: count)
        encoder.endEncoding()
        first.commit()
        first.waitUntilCompleted()
        guard first.status == .completed else { throw .gpu }

        binner.bin(count: count, rects: rects.contents().bindMemory(to: SIMD4<UInt32>.self, capacity: count),
                   depths: projected.contents().bindMemory(to: Float.self, capacity: count * Self.projectedFloats).advanced(by: 3),
                   depthStride: Self.projectedFloats, tilesX: Int(view.size.z), tileCount: view.tileCount,
                   ranges: ranges.contents().bindMemory(to: SIMD2<UInt32>.self, capacity: view.tileCount),
                   list: list.contents().bindMemory(to: UInt32.self, capacity: listCapacity), capacity: listCapacity)

        guard let second = queue.makeCommandBuffer(), let blit = second.makeBlitCommandEncoder() else { throw .gpu }
        blit.fill(buffer: screenGrads, range: 0..<(count * Self.screenStride * MemoryLayout<Float>.stride), value: 0)
        blit.endEncoding()
        var slice = UInt32(viewIndex)
        let tiles = MTLSize(width: Int(view.size.z), height: Int(view.size.w), depth: 1)
        let tileThreads = MTLSize(width: TrainingView.tile, height: TrainingView.tile, depth: 1)
        guard let raster = second.makeComputeCommandEncoder() else { throw .gpu }
        raster.setComputePipelineState(forward)
        raster.setBytes(&view, length: MemoryLayout<TrainingView>.stride, index: 0)
        raster.setBuffer(ranges, offset: 0, index: 1)
        raster.setBuffer(list, offset: 0, index: 2)
        raster.setBuffer(projected, offset: 0, index: 3)
        raster.setBuffer(pixelState, offset: 0, index: 4)
        raster.setBuffer(pixelLast, offset: 0, index: 5)
        raster.setBuffer(pixelLoss, offset: 0, index: 6)
        raster.setBytes(&slice, length: MemoryLayout<UInt32>.stride, index: 7)
        raster.setTexture(targets, index: 0)
        raster.dispatchThreadgroups(tiles, threadsPerThreadgroup: tileThreads)

        raster.setComputePipelineState(backward)
        raster.setBuffer(pixelState, offset: 0, index: 4)
        raster.setBuffer(pixelLast, offset: 0, index: 5)
        raster.setBuffer(screenGrads, offset: 0, index: 6)
        raster.dispatchThreadgroups(tiles, threadsPerThreadgroup: tileThreads)

        raster.setComputePipelineState(backwardStep)
        raster.setBuffer(params, offset: 0, index: 0)
        raster.setBuffer(projected, offset: 0, index: 1)
        raster.setBuffer(screenGrads, offset: 0, index: 2)
        raster.setBuffer(grads, offset: 0, index: 3)
        raster.setBuffer(m, offset: 0, index: 4)
        raster.setBuffer(v, offset: 0, index: 5)
        raster.setBuffer(densifyStats, offset: 0, index: 6)
        raster.setBytes(&view, length: MemoryLayout<TrainingView>.stride, index: 7)
        raster.setBytes(&step, length: MemoryLayout<Step>.stride, index: 8)
        dispatch(raster, pipeline: backwardStep, threads: count)
        raster.endEncoding()
        second.commit()
        second.waitUntilCompleted()
        guard second.status == .completed else { throw .gpu }
    }

    private func dispatch(_ encoder: any MTLComputeCommandEncoder, pipeline: any MTLComputePipelineState, threads: Int) {
        let width = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        encoder.dispatchThreadgroups(MTLSize(width: (threads + width - 1) / width, height: 1, depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
    }

    private func copy(_ source: UnsafeBufferPointer<Float>, into buffer: any MTLBuffer, count: Int) {
        guard let base = source.baseAddress, count > 0 else { return }
        buffer.contents().copyMemory(from: base, byteCount: count * MemoryLayout<Float>.stride)
    }

    private func read(_ buffer: any MTLBuffer, count: Int) -> [Float] {
        let pointer = buffer.contents().bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }
}
