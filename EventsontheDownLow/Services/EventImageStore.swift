import Foundation
import UIKit

/// Stores event photos as JPEG files on disk (under Application Support),
/// keyed by a UUID filename. SQLite only stores the filename string
/// (`CalendarEvent.imageFileName`) — the actual image bytes never touch
/// the database, which keeps the DB small and fast to query.
enum EventImageStore {

    private static var directory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EventImages", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            #if DEBUG
            print("EventImageStore: directory ready at \(dir.path)")
            #endif
        } catch {
            #if DEBUG
            print("EventImageStore: FAILED to create directory at \(dir.path): \(error)")
            #endif
        }
        return dir
    }()

    /// Saves image data (as received from PhotosPicker) as a compressed JPEG
    /// and returns the filename to store on the CalendarEvent.
    static func save(imageData: Data) -> String? {
        guard let uiImage = UIImage(data: imageData) else {
            #if DEBUG
            print("EventImageStore.save: could not decode a UIImage from the picked data (\(imageData.count) bytes)")
            #endif
            return nil
        }
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.8) else {
            #if DEBUG
            print("EventImageStore.save: UIImage decoded, but jpegData(compressionQuality:) returned nil")
            #endif
            return nil
        }
        let fileName = "\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(fileName)
        do {
            try jpegData.write(to: url, options: .atomic)
            let verifyExists = FileManager.default.fileExists(atPath: url.path)
            #if DEBUG
            print("EventImageStore.save: wrote \(jpegData.count) bytes to \(url.path) — fileExists right after write: \(verifyExists)")
            #endif
            return fileName
        } catch {
            #if DEBUG
            print("EventImageStore.save: FAILED to write to \(url.path): \(error)")
            #endif
            return nil
        }
    }

    static func url(for fileName: String?) -> URL? {
        guard let fileName else { return nil }
        let url = directory.appendingPathComponent(fileName)
        let exists = FileManager.default.fileExists(atPath: url.path)
        if !exists {
            #if DEBUG
            print("EventImageStore: no file found for '\(fileName)' at \(url.path)")
            #endif
        }
        return exists ? url : nil
    }

    static func loadData(for fileName: String?) -> Data? {
        guard let fileName else {
            #if DEBUG
            print("EventImageStore.loadData: fileName was nil")
            #endif
            return nil
        }
        guard let url = url(for: fileName) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            #if DEBUG
            print("EventImageStore: failed to read data for '\(fileName)': \(error)")
            #endif
            return nil
        }
    }

    /// Deletes the file when an event's photo is removed/replaced, or the event is deleted.
    static func delete(fileName: String?) {
        guard let fileName else { return }
        let url = directory.appendingPathComponent(fileName)
        #if DEBUG
        print("EventImageStore.delete: removing '\(fileName)' at \(url.path)")
        #endif
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            #if DEBUG
            print("EventImageStore.delete: removeItem failed (may just mean it didn't exist): \(error)")
            #endif
        }
    }

    /// Deletes any file on disk that isn't referenced by `referencedFileNames`.
    /// This catches photos that were written during an editing session (via
    /// `save(imageData:)`) that never ended up attached to a saved event —
    /// e.g. the user picked/took a photo, then tapped Cancel instead of Save.
    /// Those files aren't cleaned up at cancel-time (on purpose, to avoid
    /// ever risking deletion of a still-in-use file — see EventEditView's
    /// onChange comments), so this periodic sweep is what actually reclaims
    /// that disk space.
    @discardableResult
    static func deleteOrphanedFiles(keeping referencedFileNames: Set<String>) -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            #if DEBUG
            print("EventImageStore.deleteOrphanedFiles: couldn't list directory at \(directory.path)")
            #endif
            return 0
        }

        var deletedCount = 0
        for file in files where !referencedFileNames.contains(file) {
            let url = directory.appendingPathComponent(file)
            do {
                try FileManager.default.removeItem(at: url)
                #if DEBUG
                print("EventImageStore.deleteOrphanedFiles: removed orphaned file '\(file)'")
                #endif
                deletedCount += 1
            } catch {
                #if DEBUG
                print("EventImageStore.deleteOrphanedFiles: failed to remove '\(file)': \(error)")
                #endif
            }
        }
        if deletedCount > 0 {
            #if DEBUG
            print("EventImageStore.deleteOrphanedFiles: cleaned up \(deletedCount) orphaned file(s)")
            #endif
        }
        return deletedCount
    }
}
