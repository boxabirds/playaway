import PlayawayCore
import AppKit

/// The Mac adapter of the shared playlist sync core, one per open playlist document: it reads the state from where
/// the document's file is, moves the file through the document itself (so the window follows), and turns the
/// outcome into the one notice the person may need. It holds no state machine, destination or dialog of its own.
final class PlaylistSyncController {
    private unowned let document: PlaylistDocument
    private let services: AppServices

    init(document: PlaylistDocument, services: AppServices) {
        self.document = document
        self.services = services
    }

    var state: ICloudSyncState { playlistSyncState(of: document.fileURL, root: services.cloud.root) }

    var presentation: ICloudButtonPresentation {
        ICloudButtonPresentation(state: state, availability: services.cloud.availability)
    }

    /// Turns sync on. A press while on, or while iCloud is unavailable, changes nothing. When the playlist has just
    /// been moved into iCloud, its songs go through the one shared intake flow (story 19) with `filesPresenter`.
    @discardableResult
    @MainActor func turnOn(presenter: PlaylistPromptPresenting, filesPresenter: FilesPromptPresenting) async -> PlaylistSyncOutcome {
        guard let url = document.fileURL else { return .failed("Save the playlist before syncing it.") }   // open question 6
        let wasOn = state == .on
        let core = PlaylistSyncCore(availability: services.cloud.availability, mover: DocumentMover(document: document), presenter: presenter)
        let outcome = await core.turnOn(playlistAt: url)
        switch outcome {
        case .failed(let why): services.notices.show(.syncFailed(why))
        case .on where !wasOn: await bringSongs(presenter: filesPresenter)
        default: break
        }
        return outcome
    }

    /// The turn-on adapter of the shared flow: the playlist's songs, in order, handed to SongIntakeFlow once; the
    /// question, the transfer, the report and the messages are all the flow's. The document takes the re-pointed rows.
    @MainActor private func bringSongs(presenter: FilesPromptPresenting) async {
        let resolver = services.resolver
        let folder = document.folder
        let flow = SongIntakeFlow(root: services.cloud.root, isUbiquitous: services.cloud.isUbiquitous, resolve: { track in
            resolver.resolve(track.reference, besidePlaylistAt: folder).0.resolvedURL
        }, presenter: presenter)
        let playlist = document.playlist
        let name = document.displayName ?? ""
        let outcome = await flow.run(playlist: playlist, playlistName: name, tracks: playlist.tracks, source: .turnOnSync)
        if outcome.playlist != playlist { document.acceptTransferred(outcome.playlist) }
    }

    /// Moves the file with the file coordinator and tells it where the item went, so the document (a file presenter)
    /// learns of the move instead of taking its file for deleted and asking the person about it on the next save;
    /// then points the document at the new place, so its window title and autosave follow the file.
    private struct DocumentMover: PlaylistMoving {
        let document: PlaylistDocument
        @MainActor func movePlaylist(from source: URL, to destination: URL) async throws {
            let coordinator = NSFileCoordinator(filePresenter: document)
            var coordinationError: NSError?
            var thrown: Error?
            coordinator.coordinate(writingItemAt: source, options: .forMoving, writingItemAt: destination,
                                   options: .forReplacing, error: &coordinationError) { from, to in
                do {
                    try FileManager.default.moveItem(at: from, to: to)
                    coordinator.item(at: from, didMoveTo: to)
                } catch { thrown = error }
            }
            if let coordinationError { throw coordinationError }
            if let thrown { throw thrown }
            document.fileURL = destination
            document.fileModificationDate = try? destination.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
    }
}

/// The Playlist dialog as a sheet on the playlist's window: Move, or Don't Sync. Closing the sheet is Don't Sync.
@MainActor
final class MacPlaylistPresenter: PlaylistPromptPresenting {
    private weak var window: NSWindow?
    init(window: NSWindow?) { self.window = window }

    func askPlaylistChoice() async -> PlaylistChoice {
        let alert = NSAlert()
        alert.messageText = PlaylistPrompt.title
        alert.informativeText = PlaylistPrompt.message
        alert.addButton(withTitle: PlaylistPrompt.moveLabel)
        alert.addButton(withTitle: PlaylistPrompt.dontSyncLabel)
        let response: NSApplication.ModalResponse
        if let window {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }
        return response == .alertFirstButtonReturn ? .move : .dontSync
    }
}

/// A test seam's answer.
final class ClosurePlaylistPresenter: PlaylistPromptPresenting {
    private let ask: () async -> PlaylistChoice
    init(_ ask: @escaping () async -> PlaylistChoice) { self.ask = ask }
    func askPlaylistChoice() async -> PlaylistChoice { await ask() }
}

/// A script's answer, given in advance, so a script is never left waiting on a dialog.
final class ScriptedPlaylistPresenter: PlaylistPromptPresenting {
    private let answer: PlaylistChoice
    init(_ answer: PlaylistChoice) { self.answer = answer }
    func askPlaylistChoice() async -> PlaylistChoice { answer }
}
