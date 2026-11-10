@preconcurrency import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import UIKit

/// A walk-through video rendered from a real 3D scene.
public struct Walk3DVideo: Sendable, Equatable {
    public let fileURL: URL
    public let durationMs: Int

    public init(fileURL: URL, durationMs: Int) {
        self.fileURL = fileURL
        self.durationMs = durationMs
    }
}

public enum Walk3DRenderEvent: Sendable, Equatable {
    /// 0–1.
    case progress(Double)
    case pausedForHeat
    case finished(Walk3DVideo)
}

public enum Walk3DRenderError: Error, Sendable, Equatable {
    case invalidPackage(Walk3DImportError)
    case gpuUnavailable
    case writerFailed
    case overheated
    case cancelled
}

/// Imports the `.aar` made by `tools/walk3d/walk3d.sh` and renders the walk as an MP4.
public struct Walk3DVideoRenderer: Sendable {
    public struct Options: Sendable {
        public var width = 1080
        public var height = 1920
        public var fps = 30
        public var bitRate = 10_000_000
        /// Required by the plan; the free plan always carries it.
        public var watermark = true

        public init(width: Int = 1080, height: Int = 1920, fps: Int = 30, bitRate: Int = 10_000_000, watermark: Bool = true) {
            self.width = width
            self.height = height
            self.fps = fps
            self.bitRate = bitRate
            self.watermark = watermark
        }
    }

    /// Re-sort the Gaussians every this many frames (the camera moves a few centimeters per frame).
    static let resortInterval = 3

    private let workDirectory: URL

    public init(workDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "CasaReelWalk3DRenders", directoryHint: .isDirectory)) {
        self.workDirectory = workDirectory
    }

    public func render(package: URL, options: Options = Options()) -> AsyncThrowingStream<Walk3DRenderEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let video = try await run(package: package, options: options) { continuation.yield($0) }
                    continuation.yield(.finished(video))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? Walk3DRenderError.cancelled : error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Deletes rendered videos and unpacked scenes.
    public func purge() {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    /// Video length from the number of recovered poses: about a quarter second of walk per pose, 12–45 s.
    static func durationSeconds(keyframes: Int) -> Double {
        min(max(Double(keyframes) * 0.25, 12), 45)
    }

    private func run(package: URL, options: Options, onEvent: @Sendable (Walk3DRenderEvent) -> Void) async throws -> Walk3DVideo {
        let job = workDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: job, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
        let (scene, path) = try Self.load(package: package, into: job)
        onEvent(.progress(0))
        let renderer: SplatRenderer
        do {
            renderer = try SplatRenderer(scene: scene)
        } catch {
            throw Walk3DRenderError.gpuUnavailable
        }
        let frameCount = Int(Self.durationSeconds(keyframes: path.keyframes.count) * Double(options.fps))
        let poses = path.walk(frameCount: frameCount)
        let output = job.appending(path: "CasaReel-Walk3D.mp4")
        do {
            try await write(poses: poses, renderer: renderer, options: options, to: output, onEvent: onEvent)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        try? FileManager.default.removeItem(at: job.appending(path: "scene.splat"))
        return Walk3DVideo(fileURL: output, durationMs: poses.count * 1000 / options.fps)
    }

    static func load(package: URL, into directory: URL) throws -> (SplatScene, CameraPath) {
        let files: [String: URL]
        do {
            files = try SceneArchive.extract(["scene.splat", "path.json"], from: package, to: directory)
        } catch {
            throw Walk3DRenderError.invalidPackage(.invalidPackage)
        }
        guard let sceneURL = files["scene.splat"], let pathURL = files["path.json"] else { throw Walk3DRenderError.invalidPackage(.invalidPackage) }
        do {
            return (try SplatScene(contentsOf: sceneURL), try CameraPath(contentsOf: pathURL))
        } catch {
            throw Walk3DRenderError.invalidPackage(error)
        }
    }

    private func write(
        poses: [CameraPose], renderer: SplatRenderer, options: Options, to url: URL,
        onEvent: @Sendable (Walk3DRenderEvent) -> Void
    ) async throws {
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { throw Walk3DRenderError.writerFailed }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: options.width,
            AVVideoHeightKey: options.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: options.bitRate,
                AVVideoMaxKeyFrameIntervalKey: options.fps * 2,
                AVVideoExpectedSourceFrameRateKey: options.fps,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: options.width,
            kCVPixelBufferHeightKey as String: options.height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ])
        guard writer.canAdd(input) else { throw Walk3DRenderError.writerFailed }
        writer.add(input)
        guard writer.startWriting() else { throw Walk3DRenderError.writerFailed }
        writer.startSession(atSourceTime: .zero)
        let watermark = options.watermark ? Watermark.image(outputWidth: options.width) : nil

        do {
            for (index, pose) in poses.enumerated() {
                try Task.checkCancellation()
                try await waitWhileHot(onEvent: onEvent)
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(5))
                }
                guard let pool = adaptor.pixelBufferPool else { throw Walk3DRenderError.writerFailed }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { throw Walk3DRenderError.writerFailed }
                do {
                    try renderer.render(pose, into: buffer, resort: index % Self.resortInterval == 0)
                } catch {
                    throw Walk3DRenderError.gpuUnavailable
                }
                if let watermark { Watermark.draw(watermark, onto: buffer) }
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(options.fps))) else {
                    throw Walk3DRenderError.writerFailed
                }
                if index % 10 == 0 { onEvent(.progress(Double(index) / Double(max(poses.count, 1)))) }
            }
        } catch {
            writer.cancelWriting()
            throw error is CancellationError ? Walk3DRenderError.cancelled : error
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw Walk3DRenderError.writerFailed }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
        onEvent(.progress(1))
    }

    /// `.serious` pauses (up to 60 s); `.critical` aborts. Same policy as the photo video engine.
    private func waitWhileHot(onEvent: @Sendable (Walk3DRenderEvent) -> Void) async throws {
        var waited = 0
        while ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
            if ProcessInfo.processInfo.thermalState == .critical || waited >= 30 { throw Walk3DRenderError.overheated }
            if waited == 0 { onEvent(.pausedForHeat) }
            try await Task.sleep(for: .seconds(2))
            waited += 1
        }
    }
}

/// The "CasaReel" label of the free plan, drawn bottom right like in the photo videos.
enum Watermark {
    static func image(outputWidth: Int) -> CGImage? {
        let fontSize = CGFloat(outputWidth) * 0.035, padding = CGFloat(outputWidth) * 0.012
        let text = NSAttributedString(string: "CasaReel", attributes: [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .heavy), .foregroundColor: UIColor.white,
        ])
        let textSize = text.boundingRect(with: CGSize(width: 4000, height: fontSize * 2), options: [.usesLineFragmentOrigin], context: nil).integral.size
        let size = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.black.withAlphaComponent(0.25).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: padding).fill()
            text.draw(at: CGPoint(x: padding, y: padding))
        }.cgImage
    }

    static func draw(_ watermark: CGImage, onto buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        let margin = CGFloat(width) * 0.04
        context.setAlpha(0.85)
        context.draw(watermark, in: CGRect(x: CGFloat(width) - CGFloat(watermark.width) - margin, y: margin,
                                           width: CGFloat(watermark.width), height: CGFloat(watermark.height)))
    }
}
