import Foundation

package enum PlayRequestSource: Equatable {
    case list, next, previous, autoAdvance, startPlaylist, script, restore
}

package enum DownloadEvent: Equatable {
    case progress(SongID, reportedPercent: Double?)
    case finished(SongID)
    case failed(SongID)
}

package enum TransportPlayOutcome: Equatable { case ignored, proceed }

/// Decides what happens when a song that may not be on this device is asked for. Pure decisions; effects only through
/// the two seams. It never retries by itself and never touches playlists, order or files.
@MainActor
package final class DownloadOnPlayCoordinator {
    package private(set) var current: SongID?
    private(set) var states: [SongID: DownloadState] = [:]
    private let downloader: SongDownloading
    private let player: SongPlaybackStarting

    package init(downloader: SongDownloading, player: SongPlaybackStarting) {
        self.downloader = downloader
        self.player = player
    }

    package func state(of song: SongID) -> DownloadState { states[song] ?? .onThisDevice }

    /// A request to play `song`. `isOnDevice` is the file's presence now, supplied by the adapter.
    package func request(_ song: SongID, source: PlayRequestSource, isOnDevice: Bool) {
        current = song
        if isOnDevice {
            states[song] = .onThisDevice
            player.startPlayback(of: song)
            return
        }
        if state(of: song).isDownloading { return }   // joins the download in progress
        begin(song)
    }

    /// Transport Play: ignored while the current song downloads.
    package func transportPlay() -> TransportPlayOutcome {
        guard let current, state(of: current).isDownloading else { return .proceed }
        return .ignored
    }

    /// Tap on the pie of a download: cancel it. Nothing plays and nothing else changes.
    package func cancel(_ song: SongID) {
        guard state(of: song).isDownloading else { return }
        downloader.cancelDownload(of: song)
        states[song] = .notOnThisDevice
    }

    /// Tap on the exclamation mark: start again. Only for a failed song.
    package func retry(_ song: SongID) {
        guard state(of: song) == .failed else { return }
        begin(song)
    }

    /// Applies what the downloader reported. True when something a screen shows changed; an event that changes nothing
    /// (a progress tick with no new percentage, a report for a song no longer being fetched) is False, so a list is not
    /// redrawn twice a second for a download whose pie is not moving.
    @discardableResult
    package func handle(_ event: DownloadEvent) -> Bool {
        let song: SongID
        switch event { case .progress(let id, _), .finished(let id), .failed(let id): song = id }
        let before = state(of: song)
        switch event {
        case .progress(let song, let reported):
            guard case .downloading(let previous) = before else { return false }
            let fraction = downloadFraction(reported: reported, isDownloading: true, previous: previous)
            states[song] = .downloading(fraction ?? previous)
        case .finished(let song):
            guard before.isDownloading else { return false }
            states[song] = .onThisDevice
            if current == song { player.startPlayback(of: song) }   // another current song: keep the file, no playback
        case .failed(let song):
            guard before.isDownloading else { return false }
            states[song] = .failed
        }
        return state(of: song) != before
    }

    private func begin(_ song: SongID) {
        states[song] = .downloading(0)
        downloader.startDownload(of: song)
    }
}
