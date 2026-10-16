import Foundation

package protocol TrackResolving {
    func resolve(_ ref: TrackReference) -> (TrackStatus, TrackReference)
}

/// Follows a stored reference to the file's current place. Never throws.
/// A file moved to the Trash counts as deleted. An iCloud Drive file that has been offloaded from the device is not at
/// its path, but the system leaves a placeholder (`.<name>.icloud`) beside where it was; such a file is present as far
/// as a playlist is concerned (the app fetches it when it is played), not missing.
package struct TrackResolver: TrackResolving {
    package init() {}
    private static let trashDirectoryName = ".Trash"

    package func resolve(_ ref: TrackReference) -> (TrackStatus, TrackReference) {
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
        if !ref.lastKnownPath.isEmpty, Self.isPresent(known) {
            // A fresh bookmark when one can be made; an offloaded file may not give one, and is still the song.
            return (.resolved(known), Self.refreshed(ref, at: known) ?? ref)
        }
        return (.missing, ref)
    }

    private static func isPresent(_ url: URL) -> Bool {
        guard !url.pathComponents.contains(trashDirectoryName) else { return false }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) { return !isDirectory.boolValue }
        return iCloudPlaceholderExists(for: url)
    }

    private static func refreshed(_ ref: TrackReference, at url: URL) -> TrackReference? {
        guard let made = TrackReference.make(for: url) else { return nil }
        return TrackReference(bookmark: made.bookmark, lastKnownPath: made.lastKnownPath, fileName: ref.fileName)
    }
}

/// True when iCloud Drive has offloaded the file at `url` from this device and left its placeholder behind.
package func iCloudPlaceholderExists(for url: URL) -> Bool {
    let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
    return FileManager.default.fileExists(atPath: placeholder.path)
}
