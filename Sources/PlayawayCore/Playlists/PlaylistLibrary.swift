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
    case alreadyExists
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
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.contains(":") else { throw LibraryError.nameEmpty }
        let url = folder.appendingPathComponent(name).appendingPathExtension(playlistFileExtension)
        guard !fileManager.fileExists(atPath: url.path) else { throw LibraryError.alreadyExists }
        if case .writeFailed(let reason) = store.save(Playlist(), to: url) { throw LibraryError.writeFailed(reason) }
        return url
    }

    package func load(_ url: URL) -> LoadResult { store.load(from: url) }

    package func save(_ playlist: Playlist, to url: URL) -> SaveResult { store.save(playlist, to: url) }
}
