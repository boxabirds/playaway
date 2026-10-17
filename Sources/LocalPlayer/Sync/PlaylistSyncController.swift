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

    /// Turns sync on. A press while on, or while iCloud is unavailable, changes nothing.
    @discardableResult
    @MainActor func turnOn(presenter: PlaylistPromptPresenting) async -> PlaylistSyncOutcome {
        guard let url = document.fileURL else { return .failed("Save the playlist before syncing it.") }   // open question 6
        let core = PlaylistSyncCore(availability: services.cloud.availability, mover: DocumentMover(document: document), presenter: presenter)
        let outcome = await core.turnOn(playlistAt: url)
        if case .failed(let why) = outcome { services.notices.show(.syncFailed(why)) }
        return outcome
    }

    /// Moves the file with the file coordinator (so the document, a file presenter, is told) and points the
    /// document at the new place, so its window title and autosave follow the file.
    private struct DocumentMover: PlaylistMoving {
        let document: PlaylistDocument
        @MainActor func movePlaylist(from source: URL, to destination: URL) async throws {
            try SystemTransferFileSystem().move(source, to: destination)
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
