@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct SceneExportResult: Sendable, Equatable {
    /// The `.aar` to send to the Mac (AirDrop, Files, iCloud Drive).
    public let archiveURL: URL
    public let photoCount: Int
    public let frameCount: Int

    public init(archiveURL: URL, photoCount: Int, frameCount: Int) {
        self.archiveURL = archiveURL
        self.photoCount = photoCount
        self.frameCount = frameCount
    }
}

public enum SceneExportEvent: Sendable, Equatable {
    /// 0–1.
    case progress(Double)
    case finished(SceneExportResult)
}

public enum SceneExportError: Error, Sendable, Equatable {
    case noMedia
    /// Fewer than `SceneExporter.minImages` usable images: the 3D would not hold together.
    case notEnoughImages(found: Int)
    case unreadableMedia
    case insufficientStorage
    case writeFailed
    case cancelled
}

/// Turns gallery photos and videos into the input of the Mac reconstruction (COLMAP + Brush).
///
/// Everything is re-encoded from pixels, so EXIF, GPS, maker notes and video metadata never leave the
/// device. Layout inside the archive (one folder per camera, which COLMAP uses to share intrinsics):
///
///     manifest.json
///     images/photos/photo_001.jpg      (each photo may come from a different lens: own camera)
///     images/video_01/frame_00001.jpg  (frames of one video share one camera, in time order)
public struct SceneExporter: Sendable {
    public static let maxPhotos = 40
    /// Across all videos. With the photos this keeps COLMAP's exhaustive matching under ~1 h on an M1.
    public static let maxFrames = 200
    public static let minImages = 20
    static let maxPixelSize = 1920
    static let jpegQuality = 0.92

    private let workDirectory: URL

    public init(workDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "CasaReelWalk3D", directoryHint: .isDirectory)) {
        self.workDirectory = workDirectory
    }

    public func export(photos: [URL], videos: [URL]) -> AsyncThrowingStream<SceneExportEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await run(photos: photos, videos: videos) { continuation.yield(.progress($0)) }
                    continuation.yield(.finished(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? SceneExportError.cancelled : error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Deletes every exported scene (call when the user is done sharing, or at launch).
    public func purge() {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    private func run(photos: [URL], videos: [URL], progress: @Sendable (Double) -> Void) async throws -> SceneExportResult {
        guard !photos.isEmpty || !videos.isEmpty else { throw SceneExportError.noMedia }
        let job = workDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let scene = job.appending(path: "scene", directoryHint: .isDirectory)
        try createDirectory(scene.appending(path: "images", directoryHint: .isDirectory))
        try ensureFreeSpace()
        do {
            let photos = Array(photos.prefix(Self.maxPhotos))
            let photoCount = try writePhotos(photos, to: scene)
            progress(0.1)
            let frames = try await writeFrames(from: videos, to: scene) { progress(0.1 + 0.8 * $0) }
            let total = photoCount + frames.reduce(0, +)
            guard total >= Self.minImages else { throw SceneExportError.notEnoughImages(found: total) }
            try writeManifest(photos: photoCount, frames: frames, to: scene)
            let archive = job.appending(path: "CasaReel-Walk3D-\(Self.stamp()).aar")
            do {
                try SceneArchive.write(directory: scene, to: archive)
            } catch {
                throw SceneExportError.writeFailed
            }
            try? FileManager.default.removeItem(at: scene)
            progress(1)
            return SceneExportResult(archiveURL: archive, photoCount: photoCount, frameCount: frames.reduce(0, +))
        } catch {
            try? FileManager.default.removeItem(at: job)
            throw error
        }
    }

    // MARK: - Photos

    private func writePhotos(_ urls: [URL], to scene: URL) throws -> Int {
        guard !urls.isEmpty else { return 0 }
        let folder = scene.appending(path: "images/photos", directoryHint: .isDirectory)
        try createDirectory(folder)
        var written = 0
        for url in urls {
            try Task.checkCancellation()
            // An unreadable photo is skipped, not fatal: the others still make a scene.
            guard let image = Self.downsampledImage(at: url) else { continue }
            written += 1
            try Self.writeJPEG(image, to: folder.appending(path: String(format: "photo_%03d.jpg", written)))
        }
        return written
    }

    static func downsampledImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Pixels only: no metadata dictionary is passed, so nothing from the original file is copied.
    static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw SceneExportError.writeFailed
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw SceneExportError.writeFailed }
    }

    // MARK: - Videos

    private func writeFrames(from videos: [URL], to scene: URL, progress: (Double) -> Void) async throws -> [Int] {
        guard !videos.isEmpty else { return [] }
        let assets = videos.map { AVURLAsset(url: $0) }
        var durations: [Double] = []
        for asset in assets {
            guard let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 else {
                throw SceneExportError.unreadableMedia
            }
            durations.append(duration.seconds)
        }
        let total = durations.reduce(0, +)
        let window = FrameSelector.window(totalDuration: total, maxFrames: Self.maxFrames)
        var counts: [Int] = []
        var done = 0.0
        for (index, asset) in assets.enumerated() {
            let folder = scene.appending(path: String(format: "images/video_%02d", index + 1), directoryHint: .isDirectory)
            try createDirectory(folder)
            let count = try await writeFrames(of: asset, duration: durations[index], window: window, to: folder) { fraction in
                progress((done + fraction * durations[index]) / total)
            }
            done += durations[index]
            counts.append(count)
        }
        return counts
    }

    /// Samples two candidates per window and writes the frame the `FrameSelector` keeps.
    private func writeFrames(of asset: AVURLAsset, duration: Double, window: Double, to folder: URL, progress: (Double) -> Void) async throws -> Int {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: Self.maxPixelSize, height: Self.maxPixelSize)
        let tolerance = CMTime(seconds: window / 8, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let step = window / 2
        let times = stride(from: step / 2, to: duration, by: step).map { CMTime(seconds: $0, preferredTimescale: 600) }

        var selector = FrameSelector(window: window)
        var pending: [Double: CGImage] = [:]
        var written = 0
        func save(_ pick: FrameSelector.Candidate?) throws {
            defer { pending.removeAll() }
            guard let pick, let image = pending[pick.time] else { return }
            written += 1
            try Self.writeJPEG(image, to: folder.appending(path: String(format: "frame_%05d.jpg", written)))
        }
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            // A frame that fails to decode is just skipped.
            guard let image = try? result.image else { continue }
            let time = result.requestedTime.seconds
            let candidate = FrameSelector.Candidate(time: time, sharpness: ImageMetrics.sharpness(of: image), hash: ImageMetrics.differenceHash(of: image))
            // When this candidate opens a new window, the previous window's images are written (pick) or dropped.
            let pick = selector.add(candidate)
            if pending.keys.contains(where: { Int($0 / selector.window) != Int(time / selector.window) }) {
                try save(pick)
            }
            pending[time] = image
            progress(min(time / duration, 1))
        }
        try save(selector.finish())
        return written
    }

    // MARK: - Files

    private func writeManifest(photos: Int, frames: [Int], to scene: URL) throws {
        let manifest: [String: Any] = [
            "format": "casareel-walk3d-scene",
            "version": 1,
            "photos": photos,
            "videos": frames.enumerated().map { ["folder": String(format: "video_%02d", $0.offset + 1), "frames": $0.element] },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) else {
            throw SceneExportError.writeFailed
        }
        do {
            try data.write(to: scene.appending(path: "manifest.json"), options: [.completeFileProtectionUnlessOpen])
        } catch {
            throw SceneExportError.writeFailed
        }
    }

    private func createDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
            )
        } catch {
            throw SceneExportError.writeFailed
        }
    }

    /// Frames, archive and margin: about 400 MB in the worst case.
    private func ensureFreeSpace() throws {
        let values = try? workDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values?.volumeAvailableCapacityForImportantUsage, available < 500_000_000 {
            throw SceneExportError.insufficientStorage
        }
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }
}
