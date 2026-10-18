import Foundation

/// Why a song cannot be found on this device (story 42, with story 41's locked cloud):
/// - `needsAccess`: it is in an iCloud Drive folder this device may not read yet; restoring access finds it;
/// - `elsewhere`: it was added on another device from a place that device cannot share; nothing here can fix it;
/// - `gone`: it was on this device and is not any more (moved, renamed or deleted); the existing not-found message.
package enum UnfoundKind: Equatable { case needsAccess, elsewhere, gone }

/// Which kind of device this is, and enough about it to tell a stored path that belongs to another device from one that
/// belongs to this one. The playlist does not record which device added a song, so the path alone decides.
package struct DeviceShape: Equatable {
    package enum Platform: Equatable { case mac, iOS }
    package var platform: Platform
    /// iOS: the id in this install's own container path (`.../Containers/Data/Application/<id>/...`); nil on the Mac.
    package var ownContainerID: String?
    /// iOS: this install's home folder. A path inside it is this device's own whatever its shape (the simulator's own
    /// paths look like a Mac's).
    package var ownHome: String?

    package init(platform: Platform, ownContainerID: String? = nil, ownHome: String? = nil) {
        self.platform = platform; self.ownContainerID = ownContainerID; self.ownHome = ownHome
    }

    package static var current: DeviceShape {
        #if os(macOS)
        DeviceShape(platform: .mac)
        #else
        DeviceShape(platform: .iOS, ownContainerID: containerID(inPath: NSHomeDirectory()), ownHome: URL(fileURLWithPath: NSHomeDirectory()).canonicalPath)
        #endif
    }

    private static let applicationContainers = "/Containers/Data/Application/"
    private static func containerID(inPath path: String) -> String? {
        guard let range = path.range(of: applicationContainers) else { return nil }
        return path[range.upperBound...].split(separator: "/").first.map(String.init)
    }
    private static func isMacShaped(_ path: String) -> Bool { path.hasPrefix("/Users/") || path.hasPrefix("/Volumes/") }
    private static func isIOSShaped(_ path: String) -> Bool { path.hasPrefix("/private/var/mobile/") || path.hasPrefix("/var/mobile/") }

    /// True when the stored path belongs to another device: the other platform's shape, or an iOS app container with
    /// another id. A path inside this device's own places, or one whose shape cannot say, is not elsewhere.
    /// Limit: an iOS path in a place shared by every iOS device (another app's On My iPhone folder, File Provider
    /// storage) looks the same on all of them, so a missing one is taken as gone.
    package func addedElsewhere(path: String) -> Bool {
        guard !path.isEmpty else { return false }
        switch platform {
        case .mac:
            return Self.isIOSShaped(path)
        case .iOS:
            if let home = ownHome, path.hasPrefix(home + "/") || path == home { return false }
            if Self.isMacShaped(path) { return true }
            if Self.isIOSShaped(path), let theirs = Self.containerID(inPath: path), let ours = ownContainerID { return theirs != ours }
            return false
        }
    }
}

/// Tells the kind of a song already known not to resolve on this device. `accessNeeded` is the resolver's answer: a
/// folder this device needs permission for, or nil.
package func classifyUnfound(_ ref: TrackReference, accessNeeded: String?, device: DeviceShape) -> UnfoundKind {
    if accessNeeded != nil { return .needsAccess }
    if ref.portableLocation == nil, device.addedElsewhere(path: ref.lastKnownPath) { return .elsewhere }
    return .gone
}
