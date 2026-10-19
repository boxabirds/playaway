import SwiftUI
import PlayawayCore

// Opening a playlist without holding up the tap (audit: "clicking on a list item triggers a nontrivial amount of work").
// Reading the playlist file, looking for every song and working out which need this device's permission all used to run on
// the main thread inside the navigation. They now run in the background; the row that was tapped shows its progress once
// the work has taken longer than `OpeningProgress.delay`, and the playlist appears when it is ready.
extension AppModel {
    /// Reads and resolves the playlist, then calls `ready` on the main actor with its session. A tap on a playlist that is
    /// already opening does nothing more. `ready` is not called when the file cannot be read; the person is told instead.
    func beginOpening(_ url: URL, ready: @escaping @MainActor (PlaylistSession) -> Void) {
        if let session = sessions[url] { ready(session); return }
        guard opening[url] == nil else { return }
        let total: Int
        if case .ok(let count)? = entries.first(where: { $0.url == url })?.status { total = count } else { total = 0 }
        opening[url] = OpeningProgress(total: total)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(OpeningProgress.delay))
            self?.opening[url]?.isShown = true
        }
        let owner = library(for: url)
        let resolver = self.resolver, roots = self.roots
        let step = max(1, total / Self.openingProgressSteps)
        #if DEBUG
        let slowdown = Self.openDelay
        #else
        let slowdown: TimeInterval? = nil
        #endif
        Task.detached(priority: .userInitiated) { [weak self] in
            guard case .loaded(let playlist) = owner.load(url) else {
                await MainActor.run { self?.openingFailed(url) }
                return
            }
            let folder = url.deletingLastPathComponent()
            let tracks = playlist.tracks
            let results = PlaylistResolution.resolve(tracks, with: resolver, besidePlaylistAt: folder) { done in
                #if DEBUG
                if let slowdown { Thread.sleep(forTimeInterval: slowdown / Double(max(1, tracks.count))) }
                #endif
                if done % step == 0 || done == tracks.count { Task { @MainActor in self?.opening[url]?.done = done } }
            }
            let snapshot = AccessSnapshot.make(tracks: tracks, folder: folder, resolver: resolver, reaches: { roots.reaches($0) })
            await MainActor.run { self?.openingFinished(url, playlist: playlist, owner: owner, results: results, snapshot: snapshot, ready: ready) }
        }
    }

    private static var openingProgressSteps: Int { 50 }

    private func openingFinished(_ url: URL, playlist: Playlist, owner: PlaylistLibrary, results: [ResolvedTrack],
                                 snapshot: AccessSnapshot, ready: @MainActor (PlaylistSession) -> Void) {
        opening[url] = nil
        let session = sessions[url] ?? makeSession(url: url, playlist: playlist, owner: owner)
        for result in PlaylistResolution.current(results, in: session.playlist) {
            if case .resolved(let file) = result.status { songCache.store(result.trackID, url: file) } else { songCache.store(result.trackID, url: nil) }
        }
        accessCache[url] = (cloudRevision, snapshot)
        ready(session)
    }

    private func openingFailed(_ url: URL) {
        opening[url] = nil
        failureMessage = "That playlist can't be opened. It may be damaged or made by a newer version of Playaway."
    }

    /// A tap on a playlist in the list: the stack pushes it, a wide window selects it, both when it is ready.
    func openFromList(_ url: URL, in plan: ColumnPlan) {
        if plan != .stack { selectedPlaylist = url }                // the highlight is immediate; the songs follow
        beginOpening(url) { [weak self] _ in
            guard let self else { return }
            if plan == .stack { self.openPlaylist(url) } else { self.select(url, in: plan) }
        }
    }
}
