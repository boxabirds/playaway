import Foundation

/// How songs reached the playlist. Every one goes through the same flow and gets the same answers.
package enum IntakeSource: Equatable {
    case turnOnSync, drop, script, iPhoneAdd
}

package struct IntakeOutcome: Equatable {
    package var asked = false
    package var choice: FilesChoice?
    package var result = TransferResult()
    /// The playlist with each handled song re-pointed at its new file, order and titles unchanged.
    package var playlist: Playlist
    package init(playlist: Playlist) { self.playlist = playlist }
}

/// Where a playlist's songs are re-pointed after a transfer: each handled song keeps its place and its id.
package func repointing(_ playlist: Playlist, to newLocations: [UUID: URL]) -> Playlist {
    var updated = playlist
    updated.tracks = playlist.tracks.map { track in
        guard let url = newLocations[track.id], let reference = TrackReference.make(for: url) else { return track }
        return Track(id: track.id, reference: reference)
    }
    return updated
}

/// The single flow for songs entering an iCloud playlist, whichever way they arrive: sort the songs, ask the Files
/// question only if some need to move, transfer them, re-point the playlist and report. Adapters call this and hold no
/// branch of their own.
package struct SongIntakeFlow {
    private let root: URL?
    private let isUbiquitous: (URL) -> Bool?
    private let resolve: (Track) -> URL?
    private let fileSystem: TransferFileSystem
    private let presenter: FilesPromptPresenting
    private let fileExists: (URL) -> Bool

    /// `root` is the shared Playaway folder that songs are moved or copied into, nil when iCloud is unavailable.
    package init(root: URL?, isUbiquitous: @escaping (URL) -> Bool?, resolve: @escaping (Track) -> URL?, fileSystem: TransferFileSystem = SystemTransferFileSystem(),
                 presenter: FilesPromptPresenting, fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        self.root = root
        self.isUbiquitous = isUbiquitous
        self.resolve = resolve
        self.fileSystem = fileSystem
        self.presenter = presenter
        self.fileExists = fileExists
    }

    /// `tracks` are the songs entering (or all songs, when sync is turned on). The playlist is returned changed only
    /// when songs were moved or copied.
    package func run(playlist: Playlist, playlistName: String, tracks: [Track], source: IntakeSource) async -> IntakeOutcome {
        var outcome = IntakeOutcome(playlist: playlist)
        let files = tracks.map(resolve)
        let assessment = FileAssessor(isUbiquitous: isUbiquitous, fileExists: fileExists).assess(files)
        guard assessment.needsPrompt, let destination = transferDestination(root: root, playlistName: playlistName) else { return outcome }
        let items = zip(tracks, files).enumerated().compactMap { index, pair -> TransferItem? in
            guard assessment.classes[index] == .needsTransfer, let url = pair.1 else { return nil }
            return TransferItem(id: pair.0.id, source: url)
        }
        outcome.asked = true
        let choice = await presenter.askFilesChoice()
        outcome.choice = choice
        guard choice != .doNothing else { return outcome }
        let result = runTransfer(items, choice: choice == .moveToICloud ? .move : .copy, destination: destination, fileSystem: fileSystem)
        outcome.result = result
        outcome.playlist = repointing(playlist, to: result.newLocations)
        if choice == .moveToICloud, let report = FilesPrompt.copiedInsteadReport(result.copiedInstead) { await presenter.show(message: report) }
        if let failure = FilesPrompt.failureMessage(result.failures) { await presenter.show(message: failure) }
        return outcome
    }
}
