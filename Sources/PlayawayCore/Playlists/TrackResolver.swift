import Foundation

package protocol TrackResolving {
    func resolve(_ ref: TrackReference) -> (TrackStatus, TrackReference)
    /// The same, told where the playlist file lives, so a song the other device stored can be found beside it.
    func resolve(_ ref: TrackReference, besidePlaylistAt folder: URL?) -> (TrackStatus, TrackReference)
}

extension TrackResolving {
    package func resolve(_ ref: TrackReference, besidePlaylistAt folder: URL?) -> (TrackStatus, TrackReference) { resolve(ref) }
}

/// Follows a stored reference to the file's current place. Never throws.
/// A file moved to the Trash counts as deleted. An iCloud Drive file that has been offloaded from the device is not at
/// its path, but the system leaves a placeholder (`.<name>.icloud`) beside where it was; such a file is present as far
/// as a playlist is concerned (the app fetches it when it is played), not missing.
///
/// A reference made on another device (an iPhone playlist opened on the Mac, or the reverse) resolves by neither its
/// alias nor its path. Before such a song is called missing it is looked for at the same place inside this device's
/// copy of the iCloud Playaway folder, then beside the playlist file by its name. A song found that way is resolved
/// with the reference returned unchanged: the playlist keeps the author device's reference, which that device still
/// follows directly, and nothing is written back and forth between the two.
package struct TrackResolver: TrackResolving {
    private let cloudDocuments: URL?
    private static let trashDirectoryName = ".Trash"

    /// `cloudDocuments` is this device's copy of the iCloud Playaway folder; nil when iCloud Drive is not set up here.
    package init(cloudDocuments: URL? = CloudFolder.documentsOnThisDevice()) {
        self.cloudDocuments = cloudDocuments
    }

    package func resolve(_ ref: TrackReference) -> (TrackStatus, TrackReference) { resolve(ref, besidePlaylistAt: nil) }

    package func resolve(_ ref: TrackReference, besidePlaylistAt folder: URL?) -> (TrackStatus, TrackReference) {
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
        if let found = foundOnThisDevicesTerms(ref, besidePlaylistAt: folder) { return (.resolved(found), ref) }
        return (.missing, ref)
    }

    /// Where a song the other device stored would be on this device: the same place inside this device's iCloud
    /// Playaway folder, else beside the playlist under its name (matched as Locate matches, ignoring letter case).
    /// An offloaded placeholder counts at either place.
    private func foundOnThisDevicesTerms(_ ref: TrackReference, besidePlaylistAt folder: URL?) -> URL? {
        if let cloudDocuments, let relative = CloudFolder.relativePath(inContainer: ref.lastKnownPath) {
            let there = cloudDocuments.appendingPathComponent(relative)
            if Self.isPresent(there) { return there }
        }
        guard let folder, !ref.fileName.isEmpty, !ref.fileName.contains("/") else { return nil }
        if let match = FolderMatcher().match(missing: [(id: UUID(), fileName: ref.fileName)], in: folder).first { return match.url }
        let beside = folder.appendingPathComponent(ref.fileName)
        return iCloudPlaceholderExists(for: beside) ? beside : nil
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
