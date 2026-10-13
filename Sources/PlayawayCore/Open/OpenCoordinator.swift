import Foundation

/// Hand-over to the playlist stories. Absent by default so the audio-file path works alone.
package protocol PlaylistOpening: AnyObject {
    func canOpen(_ url: URL) -> Bool
    func open(_ url: URL)
    func endActivePlayback()
}

/// The one path every open surface (Finder double-click, Dock drop, File > Open, script) goes through.
package final class OpenCoordinator {
    private let classifier: FormatClassifying
    private let engine: PlaybackEngine
    private let notices: NoticePresenting
    private let playlists: PlaylistOpening?

    /// Called with the result of every engine play that this coordinator started.
    package var onPlayResult: ((URL, PlayResult) -> Void)?

    package init(classifier: FormatClassifying, engine: PlaybackEngine, notices: NoticePresenting,
         playlists: PlaylistOpening? = nil) {
        self.classifier = classifier
        self.engine = engine
        self.notices = notices
        self.playlists = playlists
    }

    @discardableResult
    package func open(_ url: URL) -> OpenResult {
        if let playlists, playlists.canOpen(url) {
            playlists.open(url)
            return .playlistHandedOver
        }
        switch classifier.classify(url) {
        case .unsupported(let reason):
            notices.show(.unsupported(reason))
            return .unsupported(reason)
        case .supported:
            let result = engine.play(url)
            // Only a file that really started replaces the playlist session; a failed open changes nothing.
            if result == .playing { playlists?.endActivePlayback() }
            onPlayResult?(url, result)
            return .played(result)
        }
    }

    package func open(_ urls: [URL]) {
        urls.forEach { open($0) }
    }
}

package enum OpenResult: Equatable {
    case playlistHandedOver
    case unsupported(UnsupportedReason)
    case played(PlayResult)
}
