import Foundation

/// How a playlist remembers an audio file: an Apple alias (bookmark), the last known path, the original file name,
/// and, for a file in iCloud, where it is in terms every device understands (`cloudPath`, story 40). The bookmark
/// follows the file when it moves on the device that made it; the name is used for folder matching; the cloud path is
/// what another device follows. Files written before story 40 have no cloud path; `portableLocation` derives one from
/// the stored path, so they need no re-import.
package struct TrackReference: Codable, Equatable {
    package init(bookmark: Data, lastKnownPath: String, fileName: String, cloudPath: CloudPath? = nil) {
        self.bookmark = bookmark
        self.lastKnownPath = lastKnownPath
        self.fileName = fileName
        self.cloudPath = cloudPath
    }
    package var bookmark: Data
    package var lastKnownPath: String
    package var fileName: String
    /// Absent in files from before story 40 (decoded as nil, and not written while nil, so older builds still read the file).
    package var cloudPath: CloudPath?

    /// The stored cloud path, else the one the stored path implies; nil for a file that is only on one device.
    package var portableLocation: CloudPath? { cloudPath ?? CloudPath.derive(fromPath: lastKnownPath) }
}

extension URL {
    /// The real path with every symlink resolved (`/var` is `/private/var`). Foundation's own
    /// `resolvingSymlinksInPath` strips `/private`, so the system call is used. Falls back to the plain path.
    package var canonicalPath: String {
        path.withCString { cString in
            guard let resolved = realpath(cString, nil) else { return path }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }
}

extension TrackReference {
    /// Builds a reference to an existing file. Returns nil when the file cannot be referenced.
    /// The stored path is canonical so that "did the file move?" is never decided by a symlink alone.
    package static func make(for url: URL) -> TrackReference? {
        guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return nil
        }
        let path = url.canonicalPath
        return TrackReference(bookmark: bookmark, lastKnownPath: path, fileName: url.lastPathComponent, cloudPath: CloudPath.derive(fromPath: path))
    }
}

package enum TrackStatus: Equatable {
    case resolved(URL)
    case missing
}
