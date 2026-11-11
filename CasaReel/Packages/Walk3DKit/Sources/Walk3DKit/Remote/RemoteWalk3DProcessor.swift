import Foundation
import os

/// A private Mac worker job. The API intentionally exposes no capture paths or scene data to the app.
private struct RemoteWalk3DJob: Codable, Sendable {
    let id: String
    let state: State
    let progress: Double
    let message: String?
    let videoReady: Bool

    enum State: String, Codable, Sendable {
        case queued
        case training
        case rendering
        case finished
        case failed
        case cancelled
    }
}

/// Sends an ARKit capture to the developer's Mac through HTTPS, then downloads the rendered MP4.
public final class RemoteWalk3DProcessor: @unchecked Sendable {
    private static let logger = Logger(subsystem: "br.com.casareel", category: "Walk3DRemote")
    public enum Failure: Error, Sendable, Equatable {
        case invalidConfiguration
        case archiveFailed
        case uploadFailed
        case rejected
        case failed
        case cancelled
    }

    private let baseURL: URL
    private let token: String
    private let session: URLSession
    private let outputDirectory: URL

    public init(baseURL: URL, token: String, session: URLSession? = nil,
                outputDirectory: URL = FileManager.default.temporaryDirectory.appending(path: "CasaReelRemoteWalk3D", directoryHint: .isDirectory)) {
        self.baseURL = baseURL
        self.token = token
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            // A tunnel or local Mac that disappeared must surface an actionable error instead of
            // leaving the Walk 3D screen at 0% indefinitely.
            configuration.timeoutIntervalForRequest = 45
            configuration.timeoutIntervalForResource = 10 * 60
            self.session = URLSession(configuration: configuration)
        }
        self.outputDirectory = outputDirectory
    }

    /// Uploads once and reports remote training progress. When the Mac starts rendering, a lightweight
    /// scene handle carries the remote job identifier into the existing rendering stage.
    public func train(capture: SceneCapture) -> AsyncThrowingStream<SplatTrainingEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var jobID: String?
                defer {
                    if Task.isCancelled, let jobID {
                        Task { await self.cancel(jobID: jobID) }
                    }
                }
                do {
                    Self.logger.info("Preparing Walk 3D capture upload")
                    continuation.yield(.progress(0.01))
                    let archive = try Self.archive(capture.directory)
                    defer { try? FileManager.default.removeItem(at: archive) }
                    Self.logger.info("Walk 3D capture archive is ready")
                    continuation.yield(.progress(0.04))
                    let job = try await submit(archive)
                    Self.logger.info("Walk 3D Mac job was accepted")
                    jobID = job.id
                    for try await status in statuses(jobID: job.id) {
                        switch status.state {
                        case .queued, .training:
                            continuation.yield(.progress(min(max(max(status.progress, 0.05) / 0.85, 0), 0.99)))
                        case .rendering, .finished:
                            continuation.yield(.finished(TrainedScene(
                                directory: URL(fileURLWithPath: "/remote-walk3d/", isDirectory: true).appending(path: job.id),
                                gaussians: 0
                            )))
                            continuation.finish()
                            return
                        case .failed:
                            throw Failure.failed
                        case .cancelled:
                            throw Failure.cancelled
                        }
                    }
                    continuation.finish(throwing: Failure.failed)
                } catch {
                    Self.logger.error("Walk 3D upload failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: Task.isCancelled ? Failure.cancelled : error)
                }
            }
            // Finishing the stream is the successful path after the Mac has
            // trained the scene. Only an explicit consumer cancellation should
            // stop the request (and consequently cancel the remote job).
            continuation.onTermination = { termination in
                if case .cancelled = termination { task.cancel() }
            }
        }
    }

    /// Waits for the Mac renderer and downloads its MP4 into the app's temporary directory.
    public func render(scene: TrainedScene, watermark _: Bool) -> AsyncThrowingStream<Walk3DRenderEvent, any Error> {
        AsyncThrowingStream { continuation in
            let jobID = scene.directory.lastPathComponent
            let task = Task {
                defer {
                    if Task.isCancelled {
                        Task { await self.cancel(jobID: jobID) }
                    }
                }
                do {
                    for try await status in statuses(jobID: jobID) {
                        switch status.state {
                        case .queued, .training:
                            continuation.yield(.progress(0))
                        case .rendering:
                            continuation.yield(.progress(min(max((status.progress - 0.85) / 0.15, 0), 0.99)))
                        case .finished:
                            let url = try await downloadVideo(jobID: jobID)
                            continuation.yield(.finished(Walk3DVideo(fileURL: url, durationMs: 0)))
                            continuation.finish()
                            return
                        case .failed:
                            throw Failure.failed
                        case .cancelled:
                            throw Failure.cancelled
                        }
                    }
                    continuation.finish(throwing: Failure.failed)
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? Failure.cancelled : error)
                }
            }
            // Do not cancel a completed stream: `process()` immediately starts
            // the render/download stage after training completes.
            continuation.onTermination = { termination in
                if case .cancelled = termination { task.cancel() }
            }
        }
    }

    private func submit(_ archive: URL) async throws -> RemoteWalk3DJob {
        var request = request(path: ["v1", "walk3d", "jobs"], method: "POST")
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: request, fromFile: archive)
        return try decodeJob(data, response: response)
    }

    private func statuses(jobID: String) -> AsyncThrowingStream<RemoteWalk3DJob, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        let job = try await status(jobID: jobID)
                        continuation.yield(job)
                        if [.finished, .failed, .cancelled].contains(job.state) {
                            continuation.finish()
                            return
                        }
                        try await Task.sleep(for: .seconds(2))
                    }
                    continuation.finish(throwing: Failure.cancelled)
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? Failure.cancelled : error)
                }
            }
            continuation.onTermination = { termination in
                if case .cancelled = termination { task.cancel() }
            }
        }
    }

    private func status(jobID: String) async throws -> RemoteWalk3DJob {
        let (data, response) = try await session.data(for: request(path: ["v1", "walk3d", "jobs", jobID], method: "GET"))
        return try decodeJob(data, response: response)
    }

    private func downloadVideo(jobID: String) async throws -> URL {
        let (temporary, response) = try await session.download(for: request(path: ["v1", "walk3d", "jobs", jobID, "video"], method: "GET"))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw Failure.failed }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let destination = outputDirectory.appending(path: "\(jobID).mp4")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    private func cancel(jobID: String) async {
        var request = request(path: ["v1", "walk3d", "jobs", jobID], method: "DELETE")
        request.timeoutInterval = 5
        _ = try? await session.data(for: request)
    }

    private func request(path: [String], method: String) -> URLRequest {
        let url = path.reduce(baseURL) { $0.appending(path: $1) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func decodeJob(_ data: Data, response: URLResponse) throws -> RemoteWalk3DJob {
        guard let http = response as? HTTPURLResponse else { throw Failure.rejected }
        guard (200..<300).contains(http.statusCode) else { throw Failure.rejected }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let job = try? decoder.decode(RemoteWalk3DJob.self, from: data) else { throw Failure.rejected }
        return job
    }

    private static func archive(_ directory: URL) throws -> URL {
        let archive = FileManager.default.temporaryDirectory.appending(path: "CasaReelWalk3D-\(UUID().uuidString).zip")
        do {
            try RemoteCaptureArchive.write(directory: directory, to: archive)
            return archive
        } catch {
            try? FileManager.default.removeItem(at: archive)
            throw RemoteWalk3DProcessor.Failure.archiveFailed
        }
    }
}

/// Minimal stored ZIP writer for the capture package. It streams one JPEG at a time, avoiding a large
/// in-memory multipart body or a third-party archive dependency.
enum RemoteCaptureArchive {
    private struct Entry {
        let name: Data
        let data: Data
        let checksum: UInt32
        let offset: UInt32
    }

    static func write(directory: URL, to archive: URL) throws {
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            .filter { $0 == "capture.json" || $0 == "points.bin" || $0.wholeMatch(of: /frames\/frame_\d{5}\.jpg/) != nil }
            .sorted()
        guard files.contains("capture.json"), files.contains("points.bin"), files.count >= 22 else {
            throw RemoteWalk3DProcessor.Failure.archiveFailed
        }
        FileManager.default.createFile(atPath: archive.path, contents: nil)
        let handle = try FileHandle(forWritingTo: archive)
        defer { try? handle.close() }
        var entries: [Entry] = []
        var offset: UInt32 = 0
        for path in files {
            let name = Data(path.utf8)
            let data = try Data(contentsOf: directory.appending(path: path))
            guard data.count <= Int(UInt32.max), offset <= UInt32.max - UInt32(30 + name.count + data.count) else {
                throw RemoteWalk3DProcessor.Failure.archiveFailed
            }
            let entry = Entry(name: name, data: data, checksum: crc32(data), offset: offset)
            writeLocal(entry, to: handle)
            offset += UInt32(30 + name.count + data.count)
            entries.append(entry)
        }
        let centralOffset = offset
        for entry in entries {
            writeCentral(entry, to: handle)
            offset += UInt32(46 + entry.name.count)
        }
        guard entries.count <= Int(UInt16.max) else { throw RemoteWalk3DProcessor.Failure.archiveFailed }
        // ZIP signatures are exactly four bytes. Without the explicit UInt32 cast Swift
        // infers `Int` here and writes eight bytes on arm64, corrupting every offset.
        write(UInt32(0x0605_4B50), to: handle)
        write(UInt16(0), to: handle); write(UInt16(0), to: handle)
        write(UInt16(entries.count), to: handle); write(UInt16(entries.count), to: handle)
        write(offset - centralOffset, to: handle); write(centralOffset, to: handle); write(UInt16(0), to: handle)
    }

    private static func writeLocal(_ entry: Entry, to handle: FileHandle) {
        write(UInt32(0x0403_4B50), to: handle); write(UInt16(20), to: handle); write(UInt16(0), to: handle)
        write(UInt16(0), to: handle); write(UInt16(0), to: handle); write(UInt16(0), to: handle)
        write(entry.checksum, to: handle); write(UInt32(entry.data.count), to: handle); write(UInt32(entry.data.count), to: handle)
        write(UInt16(entry.name.count), to: handle); write(UInt16(0), to: handle); handle.write(entry.name); handle.write(entry.data)
    }

    private static func writeCentral(_ entry: Entry, to handle: FileHandle) {
        write(UInt32(0x0201_4B50), to: handle); write(UInt16(20), to: handle); write(UInt16(20), to: handle)
        write(UInt16(0), to: handle); write(UInt16(0), to: handle); write(UInt16(0), to: handle); write(UInt16(0), to: handle)
        write(entry.checksum, to: handle); write(UInt32(entry.data.count), to: handle); write(UInt32(entry.data.count), to: handle)
        write(UInt16(entry.name.count), to: handle); write(UInt16(0), to: handle); write(UInt16(0), to: handle)
        write(UInt16(0), to: handle); write(UInt16(0), to: handle); write(UInt32(0), to: handle); write(entry.offset, to: handle); handle.write(entry.name)
    }

    private static func write<T: FixedWidthInteger>(_ value: T, to handle: FileHandle) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { handle.write(Data($0)) }
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xFFFF_FFFF
        for byte in data {
            value ^= UInt32(byte)
            for _ in 0..<8 { value = value & 1 == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1 }
        }
        return ~value
    }
}
