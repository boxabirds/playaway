import Foundation

/// The shared iCloud Playaway folder as it appears on each device, and the root of iCloud Drive beside it. The iPhone
/// asks the system for the Playaway folder; on the Mac it is the container's folder under Mobile Documents when iCloud
/// Drive has made one. The phone's and the Mac's copies hold the same files at the same places under `Documents`, and
/// iCloud Drive itself is the same tree under `com~apple~CloudDocs` on every device, which is what lets a path stored by
/// one device be followed on the other (`CloudPath`).
package enum CloudFolder {
    package static let containerIdentifier = "iCloud.software.away.play"
    /// The container's folder name on disk (the identifier with its dots as tildes).
    package static let containerFolderName = "iCloud~software~away~play"
    /// iCloud Drive's own folder name on disk, the root of everything the person sees in Files or Finder as iCloud Drive.
    package static let driveFolderName = "com~apple~CloudDocs"
    private static let mobileDocuments = "Library/Mobile Documents"
    private static let documentsSegment = "/" + containerFolderName + "/Documents/"
    private static let driveSegment = "/Mobile Documents/" + driveFolderName + "/"

    /// This device's copy of the Playaway folder under the given home, nil when iCloud Drive has not made one here.
    package static func documentsOnThisDevice(home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL? {
        existingDirectory(home.appendingPathComponent("\(mobileDocuments)/\(containerFolderName)/Documents", isDirectory: true))
    }

    /// This device's iCloud Drive root under the given home (the Mac reads it directly), nil when there is none.
    package static func driveRootOnThisDevice(home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL? {
        existingDirectory(home.appendingPathComponent("\(mobileDocuments)/\(driveFolderName)", isDirectory: true))
    }

    private static func existingDirectory(_ url: URL) -> URL? {
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

    /// The part of `path` after the iCloud Drive root, on whichever device the path was made; nil outside it or for the
    /// root itself. The first occurrence of the root segment is the real one (a folder of the same name inside iCloud
    /// Drive stays part of the relative path).
    package static func relativePath(inDrive path: String) -> String? {
        guard let range = path.range(of: driveSegment) else { return nil }
        let rest = String(path[range.upperBound...])
        return rest.isEmpty ? nil : rest
    }
}
