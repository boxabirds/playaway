import Foundation
import AVFoundation

/// How a playlist remembers an audio file: an Apple alias (bookmark), the last known path, the original file name,
/// and, for a file in iCloud, where it is in terms every device understands (`cloudPath`, story 40). The bookmark
/// follows the file when it moves on the device that made it; the name is used for folder matching; the cloud path is
/// what another device follows. Files written before story 40 have no cloud path; `portableLocation` derives one from
/// the stored path, so they need no re-import.
package struct TrackReference: Codable, Equatable {
    package init(bookmark: Data, lastKnownPath: String, fileName: String, cloudPath: CloudPath? = nil,
                 fileSize: Int64? = nil, duration: Double? = nil, folderName: String? = nil) {
        self.bookmark = bookmark
        self.lastKnownPath = lastKnownPath
        self.fileName = fileName
        self.cloudPath = cloudPath
        self.fileSize = fileSize
        self.duration = duration
        self.folderName = folderName
    }
    package var bookmark: Data
    package var lastKnownPath: String
    package var fileName: String
    /// Absent in files from before story 40 (decoded as nil, and not written while nil, so older builds still read the file).
    package var cloudPath: CloudPath?
    /// What helps find the song again on another device (story 41). Absent in files from before; omitted while nil.
    package var fileSize: Int64?
    package var duration: Double?
    package var folderName: String?

    /// The name of the song's folder, for grouping: the recorded name, else the folder of its cloud path, else of its stored path.
    package var groupingFolderName: String {
        if let folderName, !folderName.isEmpty { return folderName }
        if let cloudPath, let last = cloudPath.folderPath.split(separator: "/").last { return String(last) }
        return URL(fileURLWithPath: lastKnownPath).deletingLastPathComponent().lastPathComponent
    }

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
        return TrackReference(bookmark: bookmark, lastKnownPath: path, fileName: url.lastPathComponent, cloudPath: CloudPath.derive(fromPath: path),
                              fileSize: fileSize(of: url), duration: duration(of: url), folderName: url.deletingLastPathComponent().lastPathComponent)
    }
}

extension TrackReference {
    /// The file's length in bytes; nil when it cannot be read.
    static func fileSize(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map(Int64.init)
    }
    /// Seconds, read from the audio header; nil when the file is not readable audio (an empty file, a placeholder).
    static func duration(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }
}

package enum TrackStatus: Equatable {
    case resolved(URL)
    case missing
}
