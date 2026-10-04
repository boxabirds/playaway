import Foundation

struct Track: Equatable, Codable, Identifiable {
    let id: UUID
    var reference: TrackReference
}

/// A playlist is its tracks in order. Its name is its file name and is not stored inside it.
struct Playlist: Equatable {
    var tracks: [Track]

    init(tracks: [Track] = []) {
        self.tracks = tracks
    }

    func track(withID id: UUID) -> Track? {
        tracks.first { $0.id == id }
    }

    func index(ofTrackWithID id: UUID) -> Int? {
        tracks.firstIndex { $0.id == id }
    }
}

enum EditError: Error, Equatable {
    case indexOutOfRange
}

struct AddResult {
    let playlist: Playlist
    let rejected: [(url: URL, reason: UnsupportedReason)]
    let added: [Track]
}

/// Appends supported files in the order given. Unsupported files, and files no reference can be made for,
/// are returned in `rejected` and leave the playlist untouched. Never touches the audio files.
func adding(_ urls: [URL], to playlist: Playlist, classifier: FormatClassifying,
            makeReference: (URL) -> TrackReference? = TrackReference.make(for:)) -> AddResult {
    var result = playlist
    var rejected: [(url: URL, reason: UnsupportedReason)] = []
    var added: [Track] = []
    for url in urls {
        switch classifier.classify(url) {
        case .unsupported(let reason):
            rejected.append((url, reason))
        case .supported:
            guard let reference = makeReference(url) else {
                rejected.append((url, .fileNotReadable))
                continue
            }
            let track = Track(id: UUID(), reference: reference)
            result.tracks.append(track)
            added.append(track)
        }
    }
    return AddResult(playlist: result, rejected: rejected, added: added)
}

func removing(at index: Int, from playlist: Playlist) throws -> Playlist {
    guard playlist.tracks.indices.contains(index) else { throw EditError.indexOutOfRange }
    var result = playlist
    result.tracks.remove(at: index)
    return result
}

func moving(from source: Int, to destination: Int, in playlist: Playlist) throws -> Playlist {
    guard playlist.tracks.indices.contains(source), playlist.tracks.indices.contains(destination) else {
        throw EditError.indexOutOfRange
    }
    guard source != destination else { return playlist }
    var result = playlist
    let track = result.tracks.remove(at: source)
    result.tracks.insert(track, at: destination)
    return result
}
