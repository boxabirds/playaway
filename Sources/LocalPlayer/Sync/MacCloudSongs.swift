import PlayawayCore
import Foundation

/// The Mac's answers about a song file in iCloud Drive: where it is (local only, in iCloud and here, in iCloud but
/// not downloaded) and the downloads the shared coordinator asks for. The same polling the phone does; tests stand
/// in a scripted one.
protocol CloudSongsProviding: SongDownloading {
    var onEvent: ((DownloadEvent) -> Void)? { get set }
    func presence(of url: URL) -> SongPresence
}

/// A song's id on the Mac is its canonical path; the coordinator needs nothing more.
enum MacSongs {
    static func id(for url: URL) -> SongID { SongID(url.canonicalPath) }
    static func url(of song: SongID) -> URL { URL(fileURLWithPath: song.raw) }
}

/// How often a download in progress is checked, and how long it may go without the system reporting that it is
/// downloading before it is treated as failed (the same figures as the phone).
let pollInterval: TimeInterval = 0.5
let stallTimeout: TimeInterval = 30

/// What the system says about a ubiquitous file, read through one seam so tests can script it.
struct UbiquitousReading: Equatable {
    var isUbiquitous = false
    var status: String?
    var isDownloading = false
    var hasError = false
}

final class MacCloudSongs: CloudSongsProviding {
    var onEvent: ((DownloadEvent) -> Void)?
    /// Seams: the system's answers, the download request and the clock. Tests script them; the app uses the real ones.
    var read: (URL) -> UbiquitousReading = MacCloudSongs.systemReading
    var startDownloading: (URL) throws -> Void = { try FileManager.default.startDownloadingUbiquitousItem(at: $0) }
    var now: () -> Date = Date.init
    private var timers: [SongID: Timer] = [:]
    private var lastActivity: [SongID: Date] = [:]

    static func systemReading(_ url: URL) -> UbiquitousReading {
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
                                                       .ubiquitousItemIsDownloadingKey, .ubiquitousItemDownloadingErrorKey])
        return UbiquitousReading(isUbiquitous: values?.isUbiquitousItem ?? false,
                                 status: values?.ubiquitousItemDownloadingStatus?.rawValue,
                                 isDownloading: values?.ubiquitousItemIsDownloading ?? false,
                                 hasError: values?.ubiquitousItemDownloadingError != nil)
    }

    func presence(of url: URL) -> SongPresence {
        if !FileManager.default.fileExists(atPath: url.path), iCloudPlaceholderExists(for: url) { return .inCloudNotOnDevice }
        let reading = read(url)
        return songPresence(isUbiquitous: reading.isUbiquitous, downloadingStatus: reading.status)
    }

    /// Whether a download is being watched (a test aid; the timers are private).
    func isWatching(_ song: SongID) -> Bool { timers[song] != nil }

    func startDownload(of song: SongID) {
        let url = MacSongs.url(of: song)
        lastActivity[song] = now()
        do { try startDownloading(url) }
        catch { onEvent?(.failed(song)); return }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in self?.poll(song) }
        RunLoop.main.add(timer, forMode: .common)
        timers[song]?.invalidate()
        timers[song] = timer
    }

    func cancelDownload(of song: SongID) {
        finish(song)                                   // the system offers no way to stop a download; we stop watching
    }

    /// One check of a download being watched: finished when the system says the copy is here, failed on an error or
    /// after `stallTimeout` without the system reporting activity, otherwise progress (the system gives no percent).
    func poll(_ song: SongID) {
        guard timers[song] != nil else { return }
        let reading = read(MacSongs.url(of: song))
        if reading.status == ubiquitousStatusCurrent || reading.status == ubiquitousStatusDownloaded {
            finish(song); onEvent?(.finished(song)); return
        }
        if reading.hasError { finish(song); onEvent?(.failed(song)); return }
        if reading.isDownloading { lastActivity[song] = now() }
        else if let last = lastActivity[song], now().timeIntervalSince(last) > stallTimeout {
            finish(song); onEvent?(.failed(song)); return
        }
        onEvent?(.progress(song, reportedPercent: nil))
    }

    private func finish(_ song: SongID) {
        timers[song]?.invalidate(); timers[song] = nil
        lastActivity[song] = nil
    }
}

/// The player side of the shared coordinator on the Mac: when a download finishes, the song plays only if the person
/// has not asked for another song since (the player's last asked track is still this one). The current song is not
/// the measure: it also changes when a song ends or the playlist runs out, which is not the person moving on.
final class MacPlaybackStarter: SongPlaybackStarting {
    struct Pending {
        let document: PlaylistDocument
        let track: Track
    }
    var pending: [SongID: Pending] = [:]

    func startPlayback(of song: SongID) {
        guard let request = pending.removeValue(forKey: song) else { DebugTrace.log("starter: no pending request for \(song.raw)"); return }
        guard request.document.player.lastAsked?.id == request.track.id else {         // another song was asked for: keep the file, do not play
            DebugTrace.log("starter: another song was asked for since, not playing \(song.raw)"); return
        }
        request.document.player.play(track: request.track)
        DebugTrace.log("starter: played \(song.raw); session=\(request.document.player.isSessionActive) current=\(request.document.player.current?.reference.fileName ?? "nil")")
    }
}
