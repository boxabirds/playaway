import PlayawayCore
import Foundation

/// A stand-in for iCloud Drive chosen at launch by the end-to-end tests, so the built app can be driven against a
/// folder of their own and never the person's iCloud Drive. Debug builds only, like the update feed override: a
/// release build ignores the setting and uses the real Playaway folder.
///
/// `LOCALPLAYER_TEST_CLOUD_ROOT=<folder>` makes that folder the Playaway folder; the value `none` makes iCloud
/// unavailable (the signed-out case). Inside the stand-in a song is "in iCloud"; it is "not on this Mac" while only
/// its placeholder (`.<name>.icloud`) is there; a download finishes when the file appears (the test puts it there)
/// and fails when `.<name>.icloud-error` appears. Starting a download does nothing to the folder, and cancelling only
/// stops watching, as with the real system.
enum CloudStandIn {
    static let environmentKey = "LOCALPLAYER_TEST_CLOUD_ROOT"
    static let unavailableValue = "none"
    static let errorMarkerPrefix = "."
    static let errorMarkerSuffix = ".icloud-error"

    enum Setting: Equatable {
        case real
        case unavailable
        case folder(URL)
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static func setting(environment: [String: String] = ProcessInfo.processInfo.environment, debugBuild: Bool = isDebugBuild) -> Setting {
        guard debugBuild, let value = environment[environmentKey], !value.isEmpty else { return .real }
        if value == unavailableValue { return .unavailable }
        return .folder(URL(fileURLWithPath: value, isDirectory: true))
    }

    /// Where the Playaway folder is: nil for the real answer.
    static func cloudRoot(for setting: Setting) -> (() -> URL?)? {
        switch setting {
        case .real: return nil
        case .unavailable: return { nil }
        case .folder(let root): return { root }
        }
    }

    /// The stand-in's answer to "is this file in iCloud Drive": inside the folder. Nil for the real answer.
    static func isUbiquitous(for setting: Setting) -> ((URL) -> Bool?)? {
        switch setting {
        case .real: return nil
        case .unavailable: return { _ in false }
        case .folder(let root): return { url in isInside(url, root: root) }
        }
    }

    /// The Mac's cloud songs over the stand-in folder: nil for the real ones.
    static func cloudSongs(for setting: Setting) -> CloudSongsProviding? {
        guard case .folder(let root) = setting else { return nil }
        let songs = MacCloudSongs()
        songs.read = { url in reading(of: url, root: root) }
        songs.startDownloading = { url in
            DebugTrace.log("stand-in startDownloading \(url.lastPathComponent) inside=\(isInside(url, root: root))")
            guard isInside(url, root: root) else { throw CocoaError(.fileNoSuchFile) }
        }
        return songs
    }

    static func errorMarker(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(errorMarkerPrefix + url.lastPathComponent + errorMarkerSuffix)
    }

    /// A path prefix, the stand-in's own notion of "in iCloud"; the shared location rule stays in PlayawayCore. The
    /// file itself may not exist yet (a placeholder stands for it), so its folder is what is canonicalised.
    static func isInside(_ url: URL, root: URL) -> Bool {
        let folder = url.deletingLastPathComponent().canonicalPath
        return (folder + "/" + url.lastPathComponent).hasPrefix(root.canonicalPath + "/")
    }

    static func reading(of url: URL, root: URL) -> UbiquitousReading {
        guard isInside(url, root: root) else { return UbiquitousReading() }
        let here = FileManager.default.fileExists(atPath: url.path)
        return UbiquitousReading(isUbiquitous: true,
                                 status: here ? ubiquitousStatusCurrent : ubiquitousStatusNotDownloaded,
                                 isDownloading: !here,
                                 hasError: FileManager.default.fileExists(atPath: errorMarker(for: url).path))
    }
}
