import CoreGraphics
import CoreImage
import Domain
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Serializes renders: a new one starts only after the previous finished or was cancelled.
actor RenderQueue {
    private var tail: Task<Void, Never>?

    func run(_ work: @escaping @Sendable () async -> Void) async {
        let previous = tail
        let task = Task {
            await previous?.value
            await work()
        }
        tail = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

/// On-device renderer: template → timeline → frames → MP4 (+ music) → thumbnail and SHA-256.
public final class VideoEngineRenderer: VideoRenderer {
    public let templates: [VideoTemplateInfo]
    private let library: TemplateLibrary
    private let thermal: any ThermalMonitoring
    private let keepAwake: @Sendable (Bool) async -> Void
    private let outputDirectory: URL
    private let queue = RenderQueue()
    /// One Metal-backed context for every frame of every render.
    private let context = CIContext(options: [.cacheIntermediates: false, .outputPremultiplied: true])
    private let writerOptions: VideoWriter.Options

    /// - Parameter keepAwake: called with `true`/`false` around a render (the app disables the idle timer).
    public convenience init(
        library: TemplateLibrary,
        thermal: any ThermalMonitoring = SystemThermalMonitor(),
        outputDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "CasaReelRenders", directoryHint: .isDirectory),
        keepAwake: @escaping @Sendable (Bool) async -> Void = { _ in }
    ) {
        self.init(library: library, thermal: thermal, outputDirectory: outputDirectory, keepAwake: keepAwake, writerOptions: VideoWriter.Options())
    }

    init(
        library: TemplateLibrary,
        thermal: any ThermalMonitoring,
        outputDirectory: URL,
        keepAwake: @escaping @Sendable (Bool) async -> Void,
        writerOptions: VideoWriter.Options
    ) {
        self.writerOptions = writerOptions
        self.library = library
        self.templates = library.specs.map(\.info)
        self.thermal = thermal
        self.outputDirectory = outputDirectory
        self.keepAwake = keepAwake
    }

    public func render(_ request: VideoRenderRequest) -> AsyncThrowingStream<RenderEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await queue.run { [self] in
                    do {
                        let video = try await perform(request) { continuation.yield($0) }
                        continuation.yield(.finished(video))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: Task.isCancelled ? RenderError.cancelled : error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func discard(_ video: RenderedVideo) {
        for url in [video.fileURL, video.thumbnailURL] where url.standardizedFileURL.path.hasPrefix(outputDirectory.standardizedFileURL.path + "/") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Pipeline

    func timeline(for request: VideoRenderRequest) throws(RenderError) -> (TemplateSpec, SceneTimeline) {
        guard let spec = library.spec(for: request.templateSlug) else { throw .unknownTemplate }
        guard spec.aspect.contains(request.aspect) else { throw .unsupportedAspect }
        guard !request.photos.isEmpty, request.photos.count <= PhotoLimits.maximumCount else { throw .notEnoughPhotos }
        let photos = request.photos.map { photo in
            let analysis = request.analyses[photo.id]
            return (
                size: CGSize(width: photo.width, height: photo.height),
                focus: analysis?.focus ?? CGRect(x: 0, y: 0, width: 1, height: 1),
                faces: analysis?.faces ?? [],
                caption: request.captions[photo.id]
            )
        }
        return (spec, SceneTimeline.build(spec: spec, aspect: request.aspect, photos: photos, targetDurationMs: request.targetDurationMs))
    }

    private func perform(_ request: VideoRenderRequest, onEvent: @escaping @Sendable (RenderEvent) -> Void) async throws -> RenderedVideo {
        let (spec, timeline) = try timeline(for: request)
        try FileManager.default.createDirectory(
            at: outputDirectory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        )
        let id = UUID().uuidString
        let silent = outputDirectory.appending(path: "\(id)-video.mp4")
        let final = outputDirectory.appending(path: "\(id).mp4")
        let thumbnail = outputDirectory.appending(path: "\(id).jpg")
        let size = CGSize(width: request.aspect.renderSize.width, height: request.aspect.renderSize.height)
        let renderer = FrameRenderer(
            timeline: timeline, photoURLs: request.photos.map(\.fileURL), outputSize: size, context: context,
            title: request.title, watermark: request.watermark, watermarkPosition: spec.watermark?.position ?? .bottomRight
        )

        await keepAwake(true)
        defer { Task { await keepAwake(false) } }
        do {
            onEvent(.progress(0))
            try await VideoWriter(options: writerOptions, thermal: thermal).write(renderer, timeline: timeline, to: silent, onEvent: onEvent)
            if let audio = request.audioTrackURL {
                try await AudioMixer.mux(video: silent, audio: audio, fadeOutMs: spec.audio?.fadeOutMs ?? 1_000, to: final)
                try? FileManager.default.removeItem(at: silent)
            } else {
                try FileManager.default.moveItem(at: silent, to: final)
            }
            try writeThumbnail(renderer, timeline: timeline, to: thumbnail)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: final.path)
            onEvent(.progress(1))
            return RenderedVideo(
                fileURL: final, thumbnailURL: thumbnail, templateSlug: spec.slug, templateVersion: spec.version,
                aspect: request.aspect, durationMs: timeline.durationMs,
                sizeBytes: try final.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0,
                sha256: try FileDigest.sha256(of: final), watermark: request.watermark
            )
        } catch {
            for url in [silent, final, thumbnail] { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }

    /// 1280×720 (or 720×1280) JPEG from the middle of the first scene, without metadata.
    private func writeThumbnail(_ renderer: FrameRenderer, timeline: SceneTimeline, to url: URL) throws {
        let midFirstScene = (timeline.entries.first?.durationMs ?? 0) / 2
        let frame = try renderer.image(atMs: midFirstScene)
        let scale = 1280 / max(renderer.outputSize.width, renderer.outputSize.height)
        let scaled = frame.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let image = context.createCGImage(scaled, from: scaled.extent.integral),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw RenderError.writerFailed }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.writerFailed }
    }
}
