import AppleArchive
import Foundation
import System

/// Apple Archive (`.aar`, LZFSE) both ways: native on iOS and on the Mac (`aa archive` / `aa extract`), no dependencies.
enum SceneArchive {
    enum Failure: Error, Equatable {
        case cannotWrite
        case cannotRead
        case missingEntry(String)
    }

    /// Archives the contents of `directory` (paths relative to it) into `archive`.
    static func write(directory: URL, to archive: URL) throws(Failure) {
        guard let file = ArchiveByteStream.fileStream(
            path: FilePath(archive.path), mode: .writeOnly, options: [.create, .truncate],
            permissions: FilePermissions(rawValue: 0o644)
        ) else { throw .cannotWrite }
        defer { try? file.close() }
        guard let compressed = ArchiveByteStream.compressionStream(using: .lzfse, writingTo: file) else { throw .cannotWrite }
        defer { try? compressed.close() }
        guard let encoder = ArchiveStream.encodeStream(writingTo: compressed) else { throw .cannotWrite }
        defer { try? encoder.close() }
        // Only type, path, data and modes: no owners, timestamps or extended attributes leave the device.
        guard let keys = ArchiveHeader.FieldKeySet("TYP,PAT,DAT,MOD") else { throw .cannotWrite }
        do {
            try encoder.writeDirectoryContents(archiveFrom: FilePath(directory.path), keySet: keys)
        } catch {
            throw .cannotWrite
        }
    }

    /// Extracts only the named top-level regular files into `directory`; every other entry is skipped,
    /// so a hostile archive can't write elsewhere, add symlinks or fill the disk with extra files.
    static func extract(_ names: Set<String>, from archive: URL, to directory: URL) throws(Failure) -> [String: URL] {
        // The extractor finishes writing files when it closes, so all streams close before the files are checked.
        try runExtraction(names, from: archive, to: directory)
        var found: [String: URL] = [:]
        for name in names {
            let url = directory.appending(path: name)
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { throw .missingEntry(name) }
            found[name] = url
        }
        return found
    }

    private static func runExtraction(_ names: Set<String>, from archive: URL, to directory: URL) throws(Failure) {
        guard let file = ArchiveByteStream.fileStream(
            path: FilePath(archive.path), mode: .readOnly, options: [], permissions: FilePermissions(rawValue: 0o644)
        ) else { throw .cannotRead }
        defer { try? file.close() }
        guard let decompressed = ArchiveByteStream.decompressionStream(readingFrom: file) else { throw .cannotRead }
        defer { try? decompressed.close() }
        guard let decoder = ArchiveStream.decodeStream(readingFrom: decompressed) else { throw .cannotRead }
        defer { try? decoder.close() }
        let extractor = ArchiveStream.extractStream(
            extractingTo: FilePath(directory.path),
            selectUsing: { message, path, data in
                guard message == .extractBegin else { return .ok }
                guard names.contains(path.string), case .header(let header) = data,
                      let type = header.field(forKey: ArchiveHeader.FieldKey("TYP")),
                      case .uint(_, let value) = type, value == ArchiveHeader.EntryType.regularFile.rawValue
                else { return .skip }
                return .ok
            },
            flags: [.ignoreOperationNotPermitted]
        )
        guard let extractor else { throw .cannotRead }
        do {
            _ = try ArchiveStream.process(readingFrom: decoder, writingTo: extractor)
            try extractor.close()
        } catch {
            try? extractor.close()
            throw .cannotRead
        }
    }
}
