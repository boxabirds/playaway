import Foundation

package enum PlayRequestSource: Equatable {
    case list, next, previous, autoAdvance, startPlaylist, script
}

package enum DownloadEvent: Equatable {
    case progress(SongID, reportedPercent: Double?)
    case finished(SongID)
    case failed(SongID)
}

package enum TransportPlayOutcome: Equatable { case ignored, proceed }

/// Decides what happens when a song that may not be on this device is asked for. Pure decisions; effects only through
/// the two seams. It never retries by itself and never touches playlists, order or files.
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

    package func handle(_ event: DownloadEvent) {
        switch event {
        case .progress(let song, let reported):
            guard case .downloading(let previous) = state(of: song) else { return }
            let fraction = downloadFraction(reported: reported, isDownloading: true, previous: previous)
            states[song] = .downloading(fraction ?? previous)
        case .finished(let song):
            guard state(of: song).isDownloading else { return }
            states[song] = .onThisDevice
            if current == song { player.startPlayback(of: song) }   // another current song: keep the file, no playback
        case .failed(let song):
            guard state(of: song).isDownloading else { return }
            states[song] = .failed
        }
    }

    private func begin(_ song: SongID) {
        states[song] = .downloading(0)
        downloader.startDownload(of: song)
    }
}
