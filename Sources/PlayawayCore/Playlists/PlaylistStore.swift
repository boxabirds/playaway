import Foundation

package let playlistTypeIdentifier = "com.localplayer.playlist"
package let playlistFileExtension = "lplaylist"
package let playlistFormatVersion = 1

package enum SaveResult: Equatable {
    case saved
    case writeFailed(String)
}

package enum LoadResult: Equatable {
    case loaded(Playlist)
    case notFound
    case corrupt
    case unsupportedVersion(Int)
}

package protocol PlaylistStoring {
    func save(_ playlist: Playlist, to url: URL) -> SaveResult
    func load(from url: URL) -> LoadResult
}

/// File operations the store performs, so tests can inject disk-full and interruption faults at each step.
package protocol PlaylistFileOperations {
    func writeTemporary(_ data: Data, to url: URL) throws
    func replace(_ destination: URL, with temporary: URL) throws
    func remove(_ url: URL)
}

package struct SystemPlaylistFileOperations: PlaylistFileOperations {
    package init() {}
    package func writeTemporary(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.withoutOverwriting])
    }

    package func replace(_ destination: URL, with temporary: URL) throws {
        var coordinationError: NSError?
        var thrown: Error?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { coordinated in
            do {
                if FileManager.default.fileExists(atPath: coordinated.path) {
                    _ = try FileManager.default.replaceItemAt(coordinated, withItemAt: temporary)
                } else {
                    try FileManager.default.moveItem(at: temporary, to: coordinated)
                }
            } catch {
                thrown = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let thrown { throw thrown }
    }

    package func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

/// UTF-8 JSON, versioned. Writes are atomic: the new content goes to a temporary file in the same folder
/// and replaces the original in one step, so an interrupted save leaves the previous file untouched.
package struct PlaylistStore: PlaylistStoring {
    private struct Envelope: Decodable { let version: Int }
    private struct Body: Codable {
        var version: Int
        var tracks: [Track]
    }

    private static let temporaryPrefix = ".lpsave-"

    private let operations: PlaylistFileOperations

    package init(operations: PlaylistFileOperations = SystemPlaylistFileOperations()) {
        self.operations = operations
    }

    package func save(_ playlist: Playlist, to url: URL) -> SaveResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(Body(version: playlistFormatVersion, tracks: playlist.tracks))
        } catch {
            return .writeFailed(error.localizedDescription)
        }
        removeStrayTemporaries(for: url)
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent("\(Self.temporaryPrefix)\(url.lastPathComponent)-\(UUID().uuidString)")
        do {
            try operations.writeTemporary(data, to: temporary)
        } catch {
            operations.remove(temporary)
            return .writeFailed(error.localizedDescription)
        }
        do {
            try operations.replace(url, with: temporary)
        } catch {
            operations.remove(temporary)
            return .writeFailed(error.localizedDescription)
        }
        return .saved
    }

    package func load(from url: URL) -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .notFound }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return .corrupt }
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { return .corrupt }
        if envelope.version > playlistFormatVersion { return .unsupportedVersion(envelope.version) }
        guard envelope.version >= 1, let body = try? decoder.decode(Body.self, from: data) else { return .corrupt }
        return .loaded(Playlist(tracks: body.tracks))
    }

    /// A temporary left behind by an earlier interrupted save is removed on the next save.
    private func removeStrayTemporaries(for url: URL) {
        let folder = url.deletingLastPathComponent()
        let prefix = "\(Self.temporaryPrefix)\(url.lastPathComponent)-"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name.hasPrefix(prefix) {
            operations.remove(folder.appendingPathComponent(name))
        }
    }
}
