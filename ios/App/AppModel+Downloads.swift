import SwiftUI
import PlayawayCore

// Playing a song that is in iCloud and not on this device: download first, play when it arrives.
extension AppModel {
    // MARK: Download on play

    /// A song was chosen. If its file is in iCloud and not on this device it is downloaded first and plays when it
    /// has arrived; otherwise it plays at once.
    func requestPlay(_ track: Track, in session: PlaylistSession) {
        if needsAccess(track, in: session) { beginRestore(for: session); return }
        guard case .resolved(let url) = resolver.resolve(track.reference, besidePlaylistAt: session.folder).0 else {
            playExplainingFailure(track, in: session); return
        }
        let song = cloud.id(for: url)
        pendingPlays[song] = (session, track)
        downloads.request(song, source: .list, isOnDevice: cloud.presence(of: url).isOnDevice)
        cloudRevision += 1
    }

    func startPlayback(of song: SongID) {
        guard let pending = pendingPlays[song] else { return }
        if let place = pendingRestores.removeValue(forKey: song) {
            if pending.session.player.load(track: pending.track, atSeconds: place) { becameActive(pending.session) }
            cloudRevision += 1
            return
        }
        playExplainingFailure(pending.track, in: pending.session)
        cloudRevision += 1
    }

    /// Plays a song, and when it does not start says why, rather than leaving a tap that does nothing (an old playlist
    /// whose songs have moved or been deleted looked exactly like that: no sound, no controller, no word).
    func playExplainingFailure(_ track: Track, in session: PlaylistSession) {
        becameActive(session)
        session.player.play(track: track)
        guard session.player.current?.id != track.id || engine.state == .idle else { return }
        let name = track.reference.fileName
        switch resolver.resolve(track.reference, besidePlaylistAt: session.folder).0 {
        case .resolved:
            failureMessage = "“\(name)” could not be played. The file may be damaged or in a format Playaway can't play."
        default:
            if unfoundKind(for: track, in: session) == .elsewhere { failureMessage = addedElsewhereMessage; return }
            failureMessage = "“\(name)” can't be found. Its file may have been moved, renamed or deleted."
        }
    }

    /// What a song row shows about iCloud, nil when no iCloud account is available.
    /// A song's file address, found once and remembered: resolving a bookmark touches the file system, and doing it for
    /// every row on every update made scrolling jerky.
    func songURL(for track: Track, in session: PlaylistSession) -> URL? {
        switch songCache.lookup(track.id) {
        case .found(let url): return url
        case .unfound: return nil
        case .unknown:
            guard case .resolved(let url) = resolver.resolve(track.reference, besidePlaylistAt: session.folder).0 else {
                songCache.store(track.id, url: nil); return nil
            }
            songCache.store(track.id, url: url)
            return url
        }
    }

    func cloudDisplay(for track: Track, in session: PlaylistSession) -> SongRowCloudDisplay? {
        guard let url = songURL(for: track, in: session) else {
            return unfoundKind(for: track, in: session).flatMap(SongRowCloudDisplay.unfound)    // locked, question mark, or none
        }
        let song = cloud.id(for: url)
        let tracked = downloads.state(of: song)
        return SongRowCloudDisplay(presence: cloud.presence(of: url), tracked: tracked == .onThisDevice ? nil : tracked)
    }

    func cloudIconTapped(_ track: Track, session: PlaylistSession) {
        if needsAccess(track, in: session) { beginRestore(for: session); return }
        if unfoundKind(for: track, in: session) == .elsewhere { enqueueMessage(addedElsewhereMessage); return }
        guard let display = cloudDisplay(for: track, in: session), let url = songURL(for: track, in: session) else { return }
        let song = cloud.id(for: url)
        pendingPlays[song] = (session, track)
        switch cloudIconTapAction(state: display.icon, kind: .song) {
        case .cancelDownload: downloads.cancel(song)
        case .retryDownload: downloads.retry(song)
        case .openSyncDialog:
            // A song outside the Playaway folder: ask about it as for any song entering an iCloud playlist, or offer to move the
            // playlist itself if it is still only on this phone.
            if let cloudLibrary, library(for: session.url) === cloudLibrary { songsEntered([track], in: session, source: .iPhoneAdd) }
            else if let entry = entries.first(where: { $0.url == session.url }) { beginSync(entry) }
        case .none, .cancelSync, .restoreAccess, .explainElsewhere: break
        }
        cloudRevision += 1
    }
}
