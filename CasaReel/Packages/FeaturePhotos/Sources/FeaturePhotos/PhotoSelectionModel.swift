import Domain
import Foundation
import Observation

/// Something that can copy one picked photo into the preparer's staging directory.
public protocol PhotoSource: Sendable {
    func stage(into directory: URL) async throws -> URL
}

/// Selection state for one photo-set: picking, preparing, ordering and removing.
/// Photos are prepared one at a time so memory stays flat even with 40 large originals.
@Observable
@MainActor
public final class PhotoSelectionModel {
    public enum State: Equatable, Sendable {
        case preparing
        case ready(PreparedPhoto)
        case rejected(PhotoRejection)
    }

    public struct Item: Identifiable, Equatable, Sendable {
        public let id: UUID
        public internal(set) var state: State
        /// Set when an earlier photo in the list is the same picture.
        public internal(set) var duplicate: DuplicateMatch?
    }

    public private(set) var items: [Item] = []
    /// Hook for face blurring (P09); off by default.
    public var blurFaces = false

    private let preparer: any PhotoPreparing
    private var queue: [(id: UUID, source: any PhotoSource)] = []
    private var worker: Task<Void, Never>?

    public init(preparer: any PhotoPreparing) {
        self.preparer = preparer
    }

    // MARK: Derived state

    public var readyPhotos: [PreparedPhoto] {
        items.compactMap { if case .ready(let photo) = $0.state { photo } else { nil } }
    }

    public var isPreparing: Bool {
        items.contains { $0.state == .preparing }
    }

    public var rejectedCount: Int {
        items.filter { if case .rejected = $0.state { true } else { false } }.count
    }

    /// How many more photos the picker may add; rejected photos don't take a slot.
    public var remainingSlots: Int {
        max(0, PhotoLimits.maximumCount - (items.count - rejectedCount))
    }

    public var canContinue: Bool {
        !isPreparing && (PhotoLimits.minimumCount...PhotoLimits.maximumCount).contains(readyPhotos.count)
    }

    // MARK: Actions

    public func add(_ sources: [any PhotoSource]) {
        for source in sources.prefix(remainingSlots) {
            let id = UUID()
            items.append(Item(id: id, state: .preparing, duplicate: nil))
            queue.append((id, source))
        }
        startWorkerIfNeeded()
    }

    public func remove(_ id: UUID) {
        queue.removeAll { $0.id == id }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if case .ready(let photo) = items[index].state { preparer.discard(photo) }
        items.remove(at: index)
        refreshDuplicates()
    }

    public func removeRejected() {
        items.removeAll { if case .rejected = $0.state { true } else { false } }
    }

    /// Moves `id` to the position currently held by `target` (drag and drop).
    public func move(_ id: UUID, to target: UUID) {
        guard id != target,
              let from = items.firstIndex(where: { $0.id == id }),
              let to = items.firstIndex(where: { $0.id == target })
        else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)
        refreshDuplicates()
    }

    /// Abandons the selection and deletes every temporary file.
    public func reset() {
        worker?.cancel()
        worker = nil
        queue.removeAll()
        items.removeAll()
        preparer.discardAll()
    }

    /// Waits for every queued photo (tests and the continue button).
    public func waitUntilPrepared() async {
        await worker?.value
    }

    // MARK: Processing

    private func startWorkerIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, !Task.isCancelled, let next = self.dequeue() {
                let state = await self.prepare(next.source)
                guard !Task.isCancelled else {
                    if case .ready(let photo) = state { self.preparer.discard(photo) }
                    return
                }
                self.finish(next.id, with: state)
            }
            // A cancelled worker was already replaced by `reset()`; don't clear its successor.
            if !Task.isCancelled { self?.worker = nil }
        }
    }

    private func dequeue() -> (id: UUID, source: any PhotoSource)? {
        queue.isEmpty ? nil : queue.removeFirst()
    }

    private func prepare(_ source: any PhotoSource) async -> State {
        let staged: URL
        do {
            staged = try await source.stage(into: preparer.stagingDirectory)
        } catch {
            return .rejected(.unreadable)
        }
        do {
            return .ready(try await preparer.prepare(fileAt: staged))
        } catch {
            return .rejected(error)
        }
    }

    private func finish(_ id: UUID, with state: State) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            // Removed while preparing.
            if case .ready(let photo) = state { preparer.discard(photo) }
            return
        }
        items[index].state = state
        refreshDuplicates()
    }

    /// Only later copies are flagged, so the first occurrence stays clean.
    private func refreshDuplicates() {
        var earlier: [PreparedPhoto] = []
        for index in items.indices {
            guard case .ready(let photo) = items[index].state else {
                items[index].duplicate = nil
                continue
            }
            items[index].duplicate = DuplicateDetector.match(for: photo, in: earlier)
            earlier.append(photo)
        }
    }
}
