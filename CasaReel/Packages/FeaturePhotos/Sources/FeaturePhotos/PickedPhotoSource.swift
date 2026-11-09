import CoreTransferable
import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The original file of a picked photo, received as a file (streamed to disk, never loaded in memory).
struct PickedImageFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            // The received file is only valid inside this closure: move it somewhere we own.
            let inbox = FileManager.default.temporaryDirectory.appending(path: "CasaReelInbox", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let copy = inbox.appending(path: UUID().uuidString)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedImageFile(url: copy)
        }
    }
}

/// `PhotosPickerItem` adapter. The picker runs out of process, so no photo-library permission is requested.
struct PickedPhotoSource: PhotoSource {
    enum Failure: Error {
        case unavailable
    }

    let item: PhotosPickerItem

    func stage(into directory: URL) async throws -> URL {
        guard let picked = try await item.loadTransferable(type: PickedImageFile.self) else { throw Failure.unavailable }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        )
        let destination = directory.appending(path: UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: picked.url, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: picked.url)
            throw error
        }
        return destination
    }
}
