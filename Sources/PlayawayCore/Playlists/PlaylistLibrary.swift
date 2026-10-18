import Foundation

package enum PlaylistEntryStatus: Equatable {
    /// The file is listed but not read yet.
    case loading
    case ok(songCount: Int)
    case damaged
    case newerVersion(Int)
}

/// Where a playlist's file lives: in this app's own folder on the phone, or in the shared Playaway folder in iCloud.
package enum PlaylistLocation: Equatable {
    case thisPhone
    case iCloud
}

package struct PlaylistEntry: Identifiable, Equatable {
    package let url: URL
    package let name: String
    package let status: PlaylistEntryStatus
    package let location: PlaylistLocation
    package var id: URL { url }

    package init(url: URL, name: String, status: PlaylistEntryStatus, location: PlaylistLocation = .thisPhone) {
        self.url = url; self.name = name; self.status = status; self.location = location
    }
}

/// How a folder holds its playlists. On the phone each playlist is one file. In the shared iCloud folder each playlist
/// lives in a folder named after it, so the songs moved in with it travel together.
package enum PlaylistLayout: Equatable {
    case flat
    case folderPerPlaylist
}

/// Puts a file into iCloud. The iPhone's version hands the file to the system; tests use a plain move.
package protocol CloudMoving: Sendable {
    func moveIntoCloud(_ source: URL, to destination: URL) throws
}

package struct PlainFileMover: CloudMoving {
    package init() {}
    package func moveIntoCloud(_ source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }
}

package enum LibraryError: Error, Equatable {
    case nameEmpty
    case invalidCharacters
    case alreadyExists
    case notAPlaylist
    case writeFailed(String)
}

/// The playlists in one folder. Each playlist is one ordinary file; the file name is the playlist's name.
package final class PlaylistLibrary: @unchecked Sendable {      // immutable after init; its file system access is thread-safe
    package let folder: URL
    package let layout: PlaylistLayout
    private let store: PlaylistStoring
    private let fileManager: FileManager

    package init(folder: URL, layout: PlaylistLayout = .flat, store: PlaylistStoring = PlaylistStore(),
                 fileManager: FileManager = .default) {
        self.folder = folder
        self.layout = layout
        self.store = store
        self.fileManager = fileManager
    }

    private var location: PlaylistLocation { layout == .flat ? .thisPhone : .iCloud }

    /// The playlist files in this folder, one per playlist, in either layout.
    private func playlistFiles() -> [URL] {
        let items = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        switch layout {
        case .flat:
            return items.filter { $0.pathExtension == playlistFileExtension }
        case .folderPerPlaylist:
            return items.compactMap { directory in
                guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
                let file = directory.appendingPathComponent(directory.lastPathComponent).appendingPathExtension(playlistFileExtension)
                return fileManager.fileExists(atPath: file.path) ? file : nil
            }
        }
    }

    /// The playlist files by name only, without opening any of them, so a screen can show them at once and fill in
    /// counts and notes afterwards. Same order as `entries()`, so nothing moves when the rest arrives.
    package func quickEntries() -> [PlaylistEntry] {
        return playlistFiles()
            .map { PlaylistEntry(url: $0, name: $0.deletingPathExtension().lastPathComponent, status: .loading, location: location) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Playlist files in the folder, sorted by name (case-insensitive). Damaged and newer-version files are listed
    /// with their status and are never rewritten.
    package func entries() -> [PlaylistEntry] {
        return playlistFiles()
            .map { url in
                let status: PlaylistEntryStatus
                switch store.load(from: url) {
                case .loaded(let playlist): status = .ok(songCount: playlist.tracks.count)
                case .unsupportedVersion(let version): status = .newerVersion(version)
                case .corrupt, .notFound: status = .damaged
                }
                return PlaylistEntry(url: url, name: url.deletingPathExtension().lastPathComponent, status: status, location: location)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Creates an empty playlist. Refuses an empty name and refuses to replace an existing file.
    @discardableResult
    package func create(named rawName: String) throws -> URL {
        let name = try validatedName(rawName)
        if layout == .folderPerPlaylist {
            let directory = folder.appendingPathComponent(name)
            guard !fileManager.fileExists(atPath: directory.path) else { throw LibraryError.alreadyExists }
            do { try fileManager.createDirectory(at: directory, withIntermediateDirectories: true) }
            catch { throw LibraryError.writeFailed(error.localizedDescription) }
            let file = directory.appendingPathComponent(name).appendingPathExtension(playlistFileExtension)
            if case .writeFailed(let reason) = store.save(Playlist(), to: file) {
                try? fileManager.removeItem(at: directory)
                throw LibraryError.writeFailed(reason)
            }
            return file
        }
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
        if layout == .folderPerPlaylist { return try renameFolderPlaylist(url, to: name) }
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

    /// Renaming a playlist in the shared iCloud folder renames its folder and the playlist file inside it, so songs
    /// kept in the folder go with it. If the second step fails the first is undone.
    private func renameFolderPlaylist(_ url: URL, to name: String) throws -> URL {
        let oldDirectory = url.deletingLastPathComponent()
        let oldName = oldDirectory.lastPathComponent
        let newDirectory = folder.appendingPathComponent(name)
        if newDirectory.path == oldDirectory.path { return url }
        guard fileManager.fileExists(atPath: url.path) else { throw LibraryError.writeFailed("The playlist file is no longer there.") }
        let caseOnly = newDirectory.path.lowercased() == oldDirectory.path.lowercased()
        if fileManager.fileExists(atPath: newDirectory.path), !caseOnly { throw LibraryError.alreadyExists }
        do {
            if caseOnly {
                let temporary = folder.appendingPathComponent(".renaming-\(UUID().uuidString)")
                try move(oldDirectory, to: temporary)
                do { try move(temporary, to: newDirectory) } catch { try? move(temporary, to: oldDirectory); throw error }
            } else {
                try move(oldDirectory, to: newDirectory)
            }
            let oldFile = newDirectory.appendingPathComponent(oldName).appendingPathExtension(playlistFileExtension)
            let newFile = newDirectory.appendingPathComponent(name).appendingPathExtension(playlistFileExtension)
            do { try move(oldFile, to: newFile) }
            catch { try? move(newDirectory, to: oldDirectory); throw error }
            return newFile
        } catch {
            throw LibraryError.writeFailed(error.localizedDescription)
        }
    }

    /// Where a playlist lives in the shared iCloud folder: its own folder, named after it, with the file inside. One
    /// rule for both apps, so a playlist the Mac moves in is found by the phone and the other way round.
    package static func cloudPlaylistLocation(in root: URL, name: String) -> (directory: URL, file: URL) {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        return (directory, directory.appendingPathComponent(name).appendingPathExtension(playlistFileExtension))
    }

    /// Moves a playlist file from this phone into the shared iCloud folder, as `Name/Name.lplaylist`. This is the one
    /// operation that changes where files live; it moves the file, it does not copy it, and it refuses a name that is
    /// already taken, leaving the source untouched.
    @discardableResult
    package func adopt(_ source: URL, using mover: CloudMoving) throws -> URL {
        guard layout == .folderPerPlaylist else { throw LibraryError.notAPlaylist }
        guard source.pathExtension == playlistFileExtension else { throw LibraryError.notAPlaylist }
        let name = source.deletingPathExtension().lastPathComponent
        let (directory, destination) = Self.cloudPlaylistLocation(in: folder, name: name)
        guard fileManager.fileExists(atPath: source.path) else { throw LibraryError.writeFailed("The playlist file is no longer there.") }
        guard !fileManager.fileExists(atPath: directory.path) else { throw LibraryError.alreadyExists }
        do { try fileManager.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { throw LibraryError.writeFailed(error.localizedDescription) }
        do { try mover.moveIntoCloud(source, to: destination) }
        catch {
            try? fileManager.removeItem(at: directory)
            throw LibraryError.writeFailed(error.localizedDescription)
        }
        return destination
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
        if layout == .folderPerPlaylist {
            // The folder goes only if nothing else is in it: songs kept there are never deleted with the playlist.
            let directory = url.deletingLastPathComponent()
            let rest = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
            if rest.allSatisfy({ $0 == ".DS_Store" }) { try? fileManager.removeItem(at: directory) }
        }
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
