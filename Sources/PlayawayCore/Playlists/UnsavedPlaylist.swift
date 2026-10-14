import Foundation

/// Whether the playlist a song is playing from can still be found.
package enum PlaylistAvailability: Equatable {
    case available
    case deleted
    case moved
    case notDelivered
    /// A song opened on its own, with no playlist.
    case none
}

/// What tapping the playlist name on the player card does.
package enum LinkAction: Equatable {
    case navigate
    case offerSave
    case noLink
}

package func linkAction(for availability: PlaylistAvailability) -> LinkAction {
    switch availability {
    case .available: .navigate
    case .deleted, .moved, .notDelivered: .offerSave
    case .none: .noLink
    }
}

/// Lets the person pick where a playlist file goes. The implementation shows the system Files save sheet. It is
/// given a finished file and returns where it ended up, nil when the person cancelled, or throws when it could not
/// be put there.
package protocol SaveSheet {
    func save(fileAt temporary: URL, suggestedName: String) async throws -> URL?
}

package enum UnsavedSaveResult: Equatable {
    case saved(URL)
    case cancelled
    case failed(String)
}

/// Writes the songs and order of a playlist with no file as an ordinary playlist file, in the shared format, where
/// the person chooses. Nothing is left behind unless the person's chosen place received the file, and playback is
/// never touched.
package func saveUnsavedPlaylist(_ playlist: Playlist, suggestedName: String, using sheet: SaveSheet,
                                 store: PlaylistStoring = PlaylistStore(),
                                 fileManager: FileManager = .default) async -> UnsavedSaveResult {
    let folder = fileManager.temporaryDirectory.appendingPathComponent("unsaved-\(UUID().uuidString)")
    let temporary = folder.appendingPathComponent(suggestedName).appendingPathExtension(playlistFileExtension)
    defer { try? fileManager.removeItem(at: folder) }
    do { try fileManager.createDirectory(at: folder, withIntermediateDirectories: true) }
    catch { return .failed(error.localizedDescription) }
    if case .writeFailed(let reason) = store.save(playlist, to: temporary) { return .failed(reason) }
    do {
        guard let destination = try await sheet.save(fileAt: temporary, suggestedName: suggestedName) else { return .cancelled }
        return .saved(destination)
    } catch {
        return .failed(error.localizedDescription)
    }
}
