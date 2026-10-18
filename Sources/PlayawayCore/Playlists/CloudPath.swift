import Foundation

/// Where a song is in the person's iCloud, in terms every one of their devices understands: a path relative to the
/// Playaway folder (the app's own iCloud container) or relative to the root of iCloud Drive. A bookmark and an absolute
/// path (the rest of `TrackReference`) mean something only on the device that wrote them; this is the portable part.
/// Apple gives no cross-device identifier for a file outside the app's container, but iCloud Drive lays the same tree
/// out on every device under `Mobile Documents/com~apple~CloudDocs`, so the relative path names the file on all of them.
package enum CloudPath: Equatable, Hashable {
    case playawayFolder(String)
    case iCloudDrive(String)

    package var relativePath: String {
        switch self { case .playawayFolder(let path), .iCloudDrive(let path): return path }
    }

    package var isInDrive: Bool { if case .iCloudDrive = self { return true } else { return false } }

    /// The first folder under iCloud Drive, the one a device is asked to allow ("Mixdowns"): a grant of it covers every
    /// song under it. Nil for a Playaway folder path (never needs a grant) and for a file at the root (no folder to ask for).
    package var topFolder: String? {
        guard case .iCloudDrive(let path) = self else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        return parts.count >= 2 ? String(parts[0]) : nil
    }

    /// The path of the folder that holds the file ("Mixdowns/Doo-bye" for "Mixdowns/Doo-bye/a.mp3"; "" at the root).
    package var folderPath: String {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: true).dropLast()
        return parts.joined(separator: "/")
    }

    /// Read off any device's absolute path: a Mac's `/Users/x/Library/Mobile Documents/...` or an iPhone's
    /// `/private/var/mobile/Library/Mobile Documents/...`. Nil when the path is in neither place, or names the root itself.
    package static func derive(fromPath path: String) -> CloudPath? {
        if let rest = CloudFolder.relativePath(inContainer: path) { return .playawayFolder(rest) }
        if let rest = CloudFolder.relativePath(inDrive: path) { return .iCloudDrive(rest) }
        return nil
    }
}

extension CloudPath: Codable {
    private enum CodingKeys: String, CodingKey { case root, path }
    private static let playawayRoot = "playaway", driveRoot = "drive"

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let root = try container.decode(String.self, forKey: .root)
        let path = try container.decode(String.self, forKey: .path)
        switch root {
        case Self.playawayRoot: self = .playawayFolder(path)
        case Self.driveRoot: self = .iCloudDrive(path)
        default: throw DecodingError.dataCorruptedError(forKey: .root, in: container, debugDescription: "unknown cloud root \(root)")
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .playawayFolder(let path): try container.encode(Self.playawayRoot, forKey: .root); try container.encode(path, forKey: .path)
        case .iCloudDrive(let path): try container.encode(Self.driveRoot, forKey: .root); try container.encode(path, forKey: .path)
        }
    }
}
