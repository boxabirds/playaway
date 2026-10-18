import Foundation

package enum RelinkResult: Equatable {
    /// The located track first, then every other track reconnected from the same folder.
    case relinked([UUID])
    case cancelled
    case notReadable
    /// The track is no longer in the document, or is not missing, so nothing was applied.
    case editRefused
}

@MainActor
package protocol MissingTrackRelinking {
    func relink(trackID: UUID, to url: URL, in document: PlaylistDocumentEditing) -> RelinkResult
}

/// Locate: points one missing track at a chosen file, then reconnects every other missing track of the same
/// playlist whose file name is in that file's folder. Only that folder is looked at, by file name only.
@MainActor
package final class MissingTrackRelinker: MissingTrackRelinking {
    private let statuses: TrackStatusStore
    private let marks: ReadabilityMarkStoring
    private let matcher: FolderMatching
    private let makeReference: (URL) -> TrackReference?

    package init(statuses: TrackStatusStore, marks: ReadabilityMarkStoring, matcher: FolderMatching = FolderMatcher(),
         makeReference: @escaping (URL) -> TrackReference? = TrackReference.make(for:)) {
        self.statuses = statuses
        self.marks = marks
        self.matcher = matcher
        self.makeReference = makeReference
    }

    package func relink(trackID: UUID, to url: URL, in document: PlaylistDocumentEditing) -> RelinkResult {
        let playlist = document.playlist
        guard playlist.track(withID: trackID) != nil, statuses.isMissing(trackID) else { return .editRefused }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: url.path),
              let located = makeReference(url) else { return .notReadable }

        let others = playlist.tracks
            .filter { $0.id != trackID && statuses.isMissing($0.id) }
            .map { (id: $0.id, fileName: $0.reference.fileName) }
        let matches = matcher.match(missing: others, in: url.deletingLastPathComponent())

        var relinked: [UUID] = []
        func relink(_ id: UUID, to fileURL: URL, reference: TrackReference) {
            guard let track = document.playlist.track(withID: id) else { return }
            document.apply(reference, toTrack: id)
            statuses.set(.resolved(fileURL), for: id)
            marks.clearMark(of: track)
            relinked.append(id)
        }
        relink(trackID, to: url, reference: located)
        for match in matches {
            guard let reference = makeReference(match.url) else { continue }
            relink(match.id, to: match.url, reference: reference)
        }
        return .relinked(relinked)
    }
}
