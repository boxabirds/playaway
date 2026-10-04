import Foundation

/// How a playlist remembers an audio file: an Apple alias (bookmark), the last known path and the
/// original file name. The bookmark follows the file when it moves; the name is used for folder matching.
struct TrackReference: Codable, Equatable {
    var bookmark: Data
    var lastKnownPath: String
    var fileName: String
}

extension URL {
    /// The real path with every symlink resolved (`/var` is `/private/var`). Foundation's own
    /// `resolvingSymlinksInPath` strips `/private`, so the system call is used. Falls back to the plain path.
    var canonicalPath: String {
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
    static func make(for url: URL) -> TrackReference? {
        guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return nil
        }
        return TrackReference(bookmark: bookmark, lastKnownPath: url.canonicalPath, fileName: url.lastPathComponent)
    }
}

enum TrackStatus: Equatable {
    case resolved(URL)
    case missing
}
