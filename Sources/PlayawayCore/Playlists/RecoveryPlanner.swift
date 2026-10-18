import Foundation

/// A folder this device must be allowed to read, and how many songs it will bring back.
package struct RecoveryFolder: Equatable {
    package var name: String          // the top folder under iCloud Drive, "Mixdowns"
    package var drivePath: String
    package var trackCount: Int
}

package struct RecoveryPlan: Equatable {
    package var folders: [RecoveryFolder]
    package var trackCount: Int { folders.reduce(0) { $0 + $1.trackCount } }
}

/// A song the device cannot find, as the planner needs to see it.
package struct UnfoundSong: Equatable {
    package var id: UUID
    package var location: CloudPath
    package var fileName: String
    package var fileSize: Int64?
    package init(id: UUID, location: CloudPath, fileName: String, fileSize: Int64?) {
        self.id = id; self.location = location; self.fileName = fileName; self.fileSize = fileSize
    }
}

package struct RecoveryResult: Equatable {
    package enum Reason: Equatable { case notInICloudDrive, holdsNoneOfTheSongs, cancelled }
    package var restored: Int
    package var needed: Int
    package var remaining: Int { needed - restored }
    package var kept: Bool
    package var reason: Reason?
}

package enum RecoveryPlanner {
    /// The top folders to ask for, with the songs each would restore. A folder in which a song of the same playlist IS
    /// found on this device is left out: the device can read it, so its unfound songs are gone, not out of reach. Nil
    /// when nothing needs asking.
    package static func plan(unfound: [CloudPath], found: [CloudPath]) -> RecoveryPlan? {
        let readable = Set(found.compactMap(\.topFolder))
        var counts: [String: Int] = [:], order: [String] = []
        for location in unfound {
            guard let top = location.topFolder, !readable.contains(top) else { continue }
            if counts[top] == nil { order.append(top) }
            counts[top, default: 0] += 1
        }
        guard !order.isEmpty else { return nil }
        return RecoveryPlan(folders: order.map { RecoveryFolder(name: $0, drivePath: $0, trackCount: counts[$0] ?? 0) })
    }

    /// Judges a folder the person picked: keeps the permission and remembers where songs were found only when the
    /// folder is in iCloud Drive and holds at least one of the songs; otherwise nothing is kept.
    ///
    /// Songs at the place the playlist saved are checked directly, which costs nothing however big the folder is. Only
    /// songs that are not there make the folder's tree be listed (once, for all of them), and that listing reports its
    /// progress and stops when `isCancelled` says so: a big iCloud folder can take a long time to list, and nothing
    /// should freeze while it does.
    package static func apply(picked: URL?, unfound: [UnfoundSong], roots: GrantedCloudRoots, listing: FolderListing,
                              progress: (Int) -> Void = { _ in }, isCancelled: () -> Bool = { false }) -> RecoveryResult {
        let needed = unfound.count
        guard let picked else { return RecoveryResult(restored: 0, needed: needed, kept: false, reason: .cancelled) }
        guard let grant = roots.grant(pickedFolder: picked) else {
            return RecoveryResult(restored: 0, needed: needed, kept: false, reason: .notInICloudDrive)
        }
        var restored = 0, moved: [String: String] = [:]
        var notThere: [UnfoundSong] = []
        for song in unfound {
            if let url = roots.url(for: song.location), exists(url) { restored += 1 } else { notThere.append(song) }
        }
        if !notThere.isEmpty, !isCancelled() {
            let entries = listing.entries(under: picked, progress: progress, isCancelled: isCancelled)
            if !isCancelled() {
                let prefix = grant.drivePath + "/"
                let probes = notThere.map { song -> SongProbe in
                    let inside = song.location.relativePath.hasPrefix(prefix) ? String(song.location.relativePath.dropFirst(prefix.count)) : nil
                    return SongProbe(id: song.id, savedPlace: inside, fileName: song.fileName, fileSize: song.fileSize)
                }
                let outcomes = matchSongs(probes, in: entries)
                for song in notThere {
                    guard case .matched(let relative)? = outcomes[song.id] else { continue }
                    restored += 1
                    moved[song.location.relativePath] = prefix + relative
                }
            }
        }
        guard restored > 0 else {
            roots.revoke(drivePath: grant.drivePath)
            return RecoveryResult(restored: 0, needed: needed, kept: false, reason: isCancelled() ? .cancelled : .holdsNoneOfTheSongs)
        }
        roots.remember(moved)
        return RecoveryResult(restored: restored, needed: needed, kept: true, reason: nil)
    }

    private static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) || iCloudPlaceholderExists(for: url) }

    /// Where the chooser should open: iCloud Drive's folder as an iPhone or iPad lays it out. It is a hint, so a
    /// wrong one only makes the chooser open where it last was.
    package static let iOSDrivePrefix = "/private/var/mobile/Library/Mobile Documents/" + CloudFolder.driveFolderName + "/"
    package static func hint(for folder: RecoveryFolder) -> URL? {
        guard !folder.drivePath.isEmpty else { return nil }
        return URL(fileURLWithPath: iOSDrivePrefix + folder.drivePath, isDirectory: true)
    }
}
