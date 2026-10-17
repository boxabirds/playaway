import Foundation

/// The shared iCloud Playaway folder as it appears on each device. The iPhone asks the system for it; on the Mac it
/// is the container's folder under Mobile Documents when iCloud Drive has made one. The phone's and the Mac's copies
/// hold the same files at the same places under `Documents`, which is what lets a path stored by one device be
/// followed on the other.
package enum CloudFolder {
    package static let containerIdentifier = "iCloud.software.away.play"
    /// The container's folder name on disk (the identifier with its dots as tildes).
    package static let containerFolderName = "iCloud~software~away~play"
    private static let documentsSegment = "/" + containerFolderName + "/Documents/"

    /// This device's copy of the Playaway folder under the given home, nil when iCloud Drive has not made one here.
    package static func documentsOnThisDevice(home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL? {
        let url = home.appendingPathComponent("Library/Mobile Documents/\(containerFolderName)/Documents", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return url
    }

    /// The part of `path` after the container's `Documents` folder, on whichever device the path was made; nil when
    /// the path is not inside the container or names the folder itself.
    package static func relativePath(inContainer path: String) -> String? {
        guard let range = path.range(of: documentsSegment) else { return nil }
        let rest = String(path[range.upperBound...])
        return rest.isEmpty ? nil : rest
    }
}
