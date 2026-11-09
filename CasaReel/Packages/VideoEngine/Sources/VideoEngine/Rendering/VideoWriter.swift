@preconcurrency import AVFoundation
import CoreImage
import CryptoKit
import Domain
import Foundation

/// Reports the device temperature; injectable so tests can simulate heat.
public protocol ThermalMonitoring: Sendable {
    var state: ProcessInfo.ThermalState { get }
}

public struct SystemThermalMonitor: ThermalMonitoring {
    public init() {}
    public var state: ProcessInfo.ThermalState { ProcessInfo.processInfo.thermalState }
}

/// Writes frames from a `FrameRenderer` to an H.264 (or HEVC) MP4 with `AVAssetWriter`.
struct VideoWriter {
    struct Options: Sendable {
        var codec: AVVideoCodecType = .h264
        /// ~10 Mbit/s for 1080p: good for social networks without huge files.
        var bitRate = 10_000_000
        /// How long to wait for a hot device to cool down before giving up.
        var maxHeatPause: Duration = .seconds(60)
        var heatPollInterval: Duration = .seconds(2)
    }

    let options: Options
    let thermal: any ThermalMonitoring

    func write(
        _ renderer: FrameRenderer, timeline: SceneTimeline, to url: URL,
        onEvent: @Sendable (RenderEvent) -> Void
    ) async throws(RenderError) {
        let width = Int(renderer.outputSize.width), height = Int(renderer.outputSize.height)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { throw .writerFailed }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: options.codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: options.bitRate,
                AVVideoMaxKeyFrameIntervalKey: timeline.fps * 2,
                AVVideoExpectedSourceFrameRateKey: timeline.fps,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ])
        guard writer.canAdd(input) else { throw .writerFailed }
        writer.add(input)
        guard writer.startWriting() else { throw .writerFailed }
        writer.startSession(atSourceTime: .zero)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let frames = timeline.frameCount
        do {
            for frame in 0..<frames {
                try Task.checkCancellation()
                if frame.isMultiple(of: 15) { try await waitForSafeTemperature(onEvent: onEvent) }
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(2))
                }
                guard let pool = adaptor.pixelBufferPool else { throw RenderError.writerFailed }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else { throw RenderError.writerFailed }

                let timeMs = Int(Double(frame) * 1000 / Double(timeline.fps))
                let image = try renderer.image(atMs: timeMs)
                renderer.context.render(image, to: buffer, bounds: renderer.extent, colorSpace: colorSpace)
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(timeline.fps))) else {
                    throw RenderError.writerFailed
                }
                if frame.isMultiple(of: 10) { onEvent(.progress(Double(frame) / Double(frames))) }
            }
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            if error is CancellationError { throw .cancelled }
            throw (error as? RenderError) ?? .writerFailed
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            throw .writerFailed
        }
    }

    /// `.serious` pauses (polling) until the device cools down; `.critical`, or too long a pause, aborts.
    private func waitForSafeTemperature(onEvent: @Sendable (RenderEvent) -> Void) async throws {
        var waited: Duration = .zero
        var announced = false
        while true {
            switch thermal.state {
            case .critical:
                throw RenderError.overheated
            case .serious:
                if !announced { onEvent(.pausedForHeat); announced = true }
                guard waited < options.maxHeatPause else { throw RenderError.overheated }
                try await Task.sleep(for: options.heatPollInterval)
                waited += options.heatPollInterval
            default:
                return
            }
        }
    }
}

enum FileDigest {
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
