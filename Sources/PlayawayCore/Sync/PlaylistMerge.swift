import Foundation

/// One version of a playlist file as a device saw it: what it held, when it was written, and its bytes (the tie-break
/// when two versions carry the same date, so every device sorts them the same way).
package struct PlaylistVersion: Equatable {
    package let playlist: Playlist
    package let modified: Date
    package let bytes: Data

    package init(playlist: Playlist, modified: Date, bytes: Data) {
        self.playlist = playlist
        self.modified = modified
        self.bytes = bytes
    }
}

/// Merges versions of one playlist made on different devices (story 39). Deterministic: the same versions in any
/// order give the same playlist. Rules: the newest version's order is the spine; every song any version had is kept;
/// a song only in an older version goes after its nearest preceding neighbour (in its own version) that is in the
/// spine, or first if none; for the same song, a reference inside the Playaway folder beats one outside, then the
/// spine's wins. Removals are not preserved: a song removed on one device while the other still had it comes back.
package func mergedPlaylist(_ versions: [PlaylistVersion], isInContainer: (TrackReference) -> Bool) -> Playlist {
    let ordered = versions.sorted { a, b in
        if a.modified != b.modified { return a.modified > b.modified }
        return b.bytes.lexicographicallyPrecedes(a.bytes)          // greater bytes count as newer: a fixed rule, not a judgement
    }
    guard let newest = ordered.first else { return Playlist() }
    var result = newest.playlist.tracks
    var present = Set(result.map(\.id))
    var references: [UUID: TrackReference] = [:]
    for version in ordered {
        for track in version.playlist.tracks {
            if let known = references[track.id] {
                if !isInContainer(known), isInContainer(track.reference) { references[track.id] = track.reference }
            } else {
                references[track.id] = track.reference
            }
        }
    }
    for version in ordered.dropFirst() {
        let tracks = version.playlist.tracks
        for (index, track) in tracks.enumerated() where !present.contains(track.id) {
            var insertAt = 0
            var neighbour = index - 1
            while neighbour >= 0 {
                if let place = result.firstIndex(where: { $0.id == tracks[neighbour].id }) { insertAt = place + 1; break }
                neighbour -= 1
            }
            result.insert(track, at: insertAt)
            present.insert(track.id)
        }
    }
    return Playlist(tracks: result.map { Track(id: $0.id, reference: references[$0.id] ?? $0.reference) })
}
