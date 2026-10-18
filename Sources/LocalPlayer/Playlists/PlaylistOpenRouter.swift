import PlayawayCore
import AppKit

enum OpenOutcome: Equatable {
    case unreadable, empty, withTracks

    init(_ load: LoadResult) {
        switch load {
        case .loaded(let playlist): self = playlist.tracks.isEmpty ? .empty : .withTracks
        case .notFound, .corrupt, .unsupportedVersion: self = .unreadable
        }
    }
}

enum OpenAction: Equatable {
    case showAndStart, showOnly, focusOnly, doNothing
}

enum PlaylistOpenDecision {
    static func decide(_ outcome: OpenOutcome, isPlaying: Bool) -> OpenAction {
        switch outcome {
        case .unreadable: return .doNothing
        case .empty: return .showOnly
        case .withTracks: return isPlaying ? .focusOnly : .showAndStart
        }
    }
}

/// A playlist file opened from Finder: shown in its own window and started, unless it is already playing.
/// The router holds no start-position logic and never reads or writes the shuffle or repeat settings.
@MainActor
final class PlaylistOpenRouter: PlaylistOpening {
    private let controller: PlaylistDocumentController
    private let registry: ActiveSessionRegistry

    /// Called after each open with what was done, for tests and the scripting layer.
    var didOpen: ((URL, OpenAction) -> Void)?

    init(controller: PlaylistDocumentController, registry: ActiveSessionRegistry) {
        self.controller = controller
        self.registry = registry
        controller.finderOpenHandler = { [weak self] document, url, error in self?.opened(document, url: url, error: error) }
    }

    func canOpen(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == playlistFileExtension
    }

    func open(_ url: URL) {
        controller.openLikeFinder(url)
    }

    /// Decides what to do once the document is open: show it, start it, or leave it alone.
    private func opened(_ document: PlaylistDocument?, url: URL, error: Error?) {
        guard error == nil, let playlist = document else {
            didOpen?(url, .doNothing)      // unreadable: no window kept, nothing stopped, the app stays open
            return
        }
        let outcome: OpenOutcome = playlist.playlist.tracks.isEmpty ? .empty : .withTracks
        let action = PlaylistOpenDecision.decide(outcome, isPlaying: playlist.player.isPlaying)
        if action != .doNothing { playlist.showWindows() }
        if action == .showAndStart { playlist.player.start() }
        didOpen?(url, action)
    }

    func endActivePlayback() {
        registry.endActive()
    }
}
