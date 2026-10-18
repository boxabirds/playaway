import Foundation

/// The outcome of resolving one track of a playlist: where its file is on this device (or that it is missing), and the
/// reference to keep. `reference` is the reference the result was made from, so a result can be told to be stale.
package struct ResolvedTrack: Equatable {
    package var trackID: UUID
    package var reference: TrackReference
    package var status: TrackStatus
    /// The reference to store: the same as `reference`, unless the resolver refreshed it (the file moved here).
    package var refreshed: TrackReference
}

/// Resolving a playlist's files is file-system work and never belongs on the main thread. The Mac did it in the
/// background and applied the results when they arrived; the iPhone did it per row, as the row was drawn. Both now use this.
package enum PlaylistResolution {
    /// Resolves every track, in playlist order. Reads the file system only, so it is safe off the main thread.
    package static func resolve(_ tracks: [Track], with resolver: TrackResolving, besidePlaylistAt folder: URL?) -> [ResolvedTrack] {
        tracks.map { track in
            let (status, refreshed) = resolver.resolve(track.reference, besidePlaylistAt: folder)
            return ResolvedTrack(trackID: track.id, reference: track.reference, status: status, refreshed: refreshed)
        }
    }

    /// The results that are still current: a track that was removed, or whose reference changed while the resolution ran
    /// (a Locate, say), was resolved from a stale reference, and its result is dropped rather than written over newer state.
    package static func current(_ results: [ResolvedTrack], in playlist: Playlist) -> [ResolvedTrack] {
        results.filter { playlist.track(withID: $0.trackID)?.reference == $0.reference }
    }

    /// `resolve` on a background thread. `observing` is called on that thread before the work, for tests.
    package static func resolveInBackground(_ tracks: [Track], with resolver: TrackResolving, besidePlaylistAt folder: URL?,
                                            observing: @escaping @Sendable () -> Void = {}) async -> [ResolvedTrack] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                observing()
                continuation.resume(returning: resolve(tracks, with: resolver, besidePlaylistAt: folder))
            }
        }
    }
}

/// What a screen reads while it draws: the last resolution of each track. A track that has not been resolved yet has no
/// answer at all, which is not the same as missing.
package struct ResolutionSnapshot: Equatable {
    private let byTrack: [UUID: ResolvedTrack]

    package init(_ results: [ResolvedTrack] = []) {
        byTrack = Dictionary(results.map { ($0.trackID, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    package var isEmpty: Bool { byTrack.isEmpty }
    package func status(for id: UUID) -> TrackStatus? { byTrack[id]?.status }
    package func url(for id: UUID) -> URL? {
        if case .resolved(let url)? = byTrack[id]?.status { return url }
        return nil
    }
    package func refreshed(for id: UUID) -> TrackReference? { byTrack[id]?.refreshed }
}
