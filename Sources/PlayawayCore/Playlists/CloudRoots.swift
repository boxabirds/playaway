import Foundation

/// Where a portable `CloudPath` is on this device, if anywhere. The Mac answers from folders it reads directly
/// (`DirectCloudRoots`); the iPhone and iPad answer from the Playaway container and the folders the person has allowed
/// (`GrantedCloudRoots`).
package protocol CloudRoots {
    /// A URL on this device for the path, or nil when this device cannot reach it (no such root here, or no permission).
    func url(for path: CloudPath) -> URL?
    /// The folder a permission would be asked for when `url(for:)` is nil for want of one; nil where none would help
    /// (the Mac, a Playaway folder path, a file at the drive root).
    func accessNeeded(for path: CloudPath) -> String?
}

/// Both roots read directly, as the unsandboxed Mac app can. A root that is nil is not on this device.
package struct DirectCloudRoots: CloudRoots {
    package var playawayDocuments: URL?
    package var driveRoot: URL?

    package init(playawayDocuments: URL?, driveRoot: URL?) {
        self.playawayDocuments = playawayDocuments
        self.driveRoot = driveRoot
    }

    package func url(for path: CloudPath) -> URL? {
        switch path {
        case .playawayFolder(let rest): return playawayDocuments.flatMap { appending(rest, to: $0) }
        case .iCloudDrive(let rest): return driveRoot.flatMap { appending(rest, to: $0) }
        }
    }

    package func accessNeeded(for path: CloudPath) -> String? { nil }
}

/// `rest` placed under `root`, refusing a path that would climb out of it.
package func appending(_ rest: String, to root: URL) -> URL? {
    let parts = rest.split(separator: "/", omittingEmptySubsequences: true)
    guard !parts.isEmpty, !parts.contains("..") else { return nil }
    return root.appendingPathComponent(parts.joined(separator: "/"))
}
