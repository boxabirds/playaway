import Foundation

protocol TrackResolving {
    func resolve(_ ref: TrackReference) -> (TrackStatus, TrackReference)
}

/// Follows a stored reference to the file's current place. Never throws.
/// A file moved to the Trash counts as deleted.
struct TrackResolver: TrackResolving {
    private static let trashDirectoryName = ".Trash"

    func resolve(_ ref: TrackReference) -> (TrackStatus, TrackReference) {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: ref.bookmark, options: [.withoutUI, .withoutMounting],
                              relativeTo: nil, bookmarkDataIsStale: &stale),
           Self.isPresent(url) {
            if stale || url.canonicalPath != ref.lastKnownPath, let refreshed = Self.refreshed(ref, at: url) {
                return (.resolved(url), refreshed)
            }
            return (.resolved(url), ref)
        }
        let known = URL(fileURLWithPath: ref.lastKnownPath)
        if !ref.lastKnownPath.isEmpty, Self.isPresent(known), let rebuilt = Self.refreshed(ref, at: known) {
            return (.resolved(known), rebuilt)
        }
        return (.missing, ref)
    }

    private static func isPresent(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return !url.pathComponents.contains(trashDirectoryName)
    }

    private static func refreshed(_ ref: TrackReference, at url: URL) -> TrackReference? {
        guard let made = TrackReference.make(for: url) else { return nil }
        return TrackReference(bookmark: made.bookmark, lastKnownPath: made.lastKnownPath, fileName: ref.fileName)
    }
}
