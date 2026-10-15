import Foundation

package enum PlaylistEntryStatus: Equatable {
    /// The file is listed but not read yet.
    case loading
    case ok(songCount: Int)
    case damaged
    case newerVersion(Int)
}

package struct PlaylistEntry: Identifiable, Equatable {
    package let url: URL
    package let name: String
    package let status: PlaylistEntryStatus
    package var id: URL { url }
}

package enum LibraryError: Error, Equatable {
    case nameEmpty
    case invalidCharacters
    case alreadyExists
    case notAPlaylist
    case writeFailed(String)
}

/// The playlists in one folder. Each playlist is one ordinary file; the file name is the playlist's name.
package final class PlaylistLibrary {
    package let folder: URL
    private let store: PlaylistStoring
    private let fileManager: FileManager

    package init(folder: URL, store: PlaylistStoring = PlaylistStore(), fileManager: FileManager = .default) {
        self.folder = folder
        self.store = store
        self.fileManager = fileManager
    }

    /// The playlist files by name only, without opening any of them, so a screen can show them at once and fill in
    /// counts and notes afterwards. Same order as `entries()`, so nothing moves when the rest arrives.
    package func quickEntries() -> [PlaylistEntry] {
        let urls = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == playlistFileExtension }
            .map { PlaylistEntry(url: $0, name: $0.deletingPathExtension().lastPathComponent, status: .loading) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Playlist files in the folder, sorted by name (case-insensitive). Damaged and newer-version files are listed
    /// with their status and are never rewritten.
    package func entries() -> [PlaylistEntry] {
        let urls = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == playlistFileExtension }
            .map { url in
                let status: PlaylistEntryStatus
                switch store.load(from: url) {
                case .loaded(let playlist): status = .ok(songCount: playlist.tracks.count)
                case .unsupportedVersion(let version): status = .newerVersion(version)
                case .corrupt, .notFound: status = .damaged
                }
                return PlaylistEntry(url: url, name: url.deletingPathExtension().lastPathComponent, status: status)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Creates an empty playlist. Refuses an empty name and refuses to replace an existing file.
    @discardableResult
    package func create(named rawName: String) throws -> URL {
        let name = try validatedName(rawName)
        let url = folder.appendingPathComponent(name).appendingPathExtension(playlistFileExtension)
        guard !fileManager.fileExists(atPath: url.path) else { throw LibraryError.alreadyExists }
        if case .writeFailed(let reason) = store.save(Playlist(), to: url) { throw LibraryError.writeFailed(reason) }
        return url
    }

    /// The name with surrounding spaces removed, or the reason it cannot be used.
    private func validatedName(_ rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LibraryError.nameEmpty }
        guard !name.contains("/"), !name.contains(":") else { throw LibraryError.invalidCharacters }
        return name
    }

    /// Renames a playlist by moving its file within its folder. The songs, their order and the file's contents are
    /// untouched, and the playlist is always present under either the old or the new name. Renaming to the name it
    /// already has does nothing; a name differing only in letter case renames it.
    @discardableResult
    package func rename(_ url: URL, to rawName: String) throws -> URL {
        let name = try validatedName(rawName)
        let target = url.deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension(playlistFileExtension)
        if target.path == url.path { return url }
        guard fileManager.fileExists(atPath: url.path) else { throw LibraryError.writeFailed("The playlist file is no longer there.") }
        let caseOnly = target.path.lowercased() == url.path.lowercased()
        if fileManager.fileExists(atPath: target.path), !caseOnly { throw LibraryError.alreadyExists }
        do {
            if caseOnly {
                // On a case-insensitive volume the two names are one file: go through a temporary name.
                let temporary = url.deletingLastPathComponent().appendingPathComponent(".renaming-\(UUID().uuidString)")
                try move(url, to: temporary)
                do { try move(temporary, to: target) } catch { try? move(temporary, to: url); throw error }
            } else {
                try move(url, to: target)
            }
        } catch {
            throw LibraryError.writeFailed(error.localizedDescription)
        }
        return target
    }

    /// Deletes a playlist's file and nothing else: never a song file, never another playlist. Anything that is not a
    /// playlist file is refused. Where the folder is in iCloud Drive, the system keeps the file in its own Recently
    /// Deleted place; elsewhere the delete is final.
    package func delete(_ url: URL) throws {
        guard url.pathExtension == playlistFileExtension else { throw LibraryError.notAPlaylist }
        guard fileManager.fileExists(atPath: url.path) else { throw LibraryError.writeFailed("The playlist file is no longer there.") }
        var coordinationError: NSError?
        var thrown: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { coordinated in
            do { try fileManager.removeItem(at: coordinated) } catch { thrown = error }
        }
        if let error = coordinationError ?? thrown.map({ $0 as NSError }) { throw LibraryError.writeFailed(error.localizedDescription) }
    }

    private func move(_ source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var thrown: Error?
        NSFileCoordinator().coordinate(writingItemAt: source, options: .forMoving, writingItemAt: destination,
                                       options: .forReplacing, error: &coordinationError) { from, to in
            do { try fileManager.moveItem(at: from, to: to) } catch { thrown = error }
        }
        if let coordinationError { throw coordinationError }
        if let thrown { throw thrown }
    }

    package func load(_ url: URL) -> LoadResult { store.load(from: url) }

    package func save(_ playlist: Playlist, to url: URL) -> SaveResult { store.save(playlist, to: url) }
}
