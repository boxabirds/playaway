import Foundation

/// What a playlist needs on this device: the songs that cannot be found and whose folder this device may not read, the plan
/// to ask for those folders, and which songs show the locked cloud (story 41).
package struct AccessSnapshot: Equatable {
    package var plan: RecoveryPlan?
    package var unfound: [UnfoundSong]
    package var locked: Set<UUID>

    package init(plan: RecoveryPlan?, unfound: [UnfoundSong], locked: Set<UUID>) {
        self.plan = plan; self.unfound = unfound; self.locked = locked
    }

    package static let empty = AccessSnapshot(plan: nil, unfound: [], locked: [])

    /// Looks at every song with a place in iCloud Drive. A folder in which some song of the playlist IS found is never
    /// asked for. File-system work: never on the main thread for a big playlist. `progress` hears the count looked at.
    package static func make(tracks: [Track], folder: URL?, resolver: TrackResolving, reaches: (CloudPath) -> Bool,
                             progress: (Int) -> Void = { _ in }) -> AccessSnapshot {
        var unfound: [UnfoundSong] = [], found: [CloudPath] = []
        for (index, track) in tracks.enumerated() {
            defer { progress(index + 1) }
            guard let location = track.reference.portableLocation, location.isInDrive else { continue }
            if resolver.accessNeeded(for: track.reference, besidePlaylistAt: folder) != nil {
                unfound.append(UnfoundSong(id: track.id, location: location, fileName: track.reference.fileName, fileSize: track.reference.fileSize))
            } else if case .resolved = resolver.resolve(track.reference, besidePlaylistAt: folder).0, !reaches(location) {
                found.append(location)      // found by its own means, not through a permission given here: the folder is readable
            }
        }
        let plan = RecoveryPlanner.plan(unfound: unfound.map(\.location), found: found)
        let planned = Set(plan?.folders.map(\.name) ?? [])
        let needing = unfound.filter { planned.contains($0.location.topFolder ?? "") }
        return AccessSnapshot(plan: plan, unfound: needing, locked: Set(needing.map(\.id)))
    }
}

/// What a row shows while a playlist is being opened. The system's own press highlight is the first feedback; this is the
/// second, for work that takes long enough to be noticed: after `delay` the row says what is going on and how far it is.
package struct OpeningProgress: Equatable {
    /// How long an open may take before it shows progress. Under this the open just happens.
    package static let delay: TimeInterval = 0.3

    package var done: Int
    package var total: Int
    package var isShown: Bool

    package init(done: Int = 0, total: Int, isShown: Bool = false) { self.done = done; self.total = total; self.isShown = isShown }

    /// 0...1; an empty playlist is complete.
    package var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 1 }
    /// "Loading 12 of 45"
    package var label: String { "Loading \(min(done, total)) of \(total)" }

    /// True when the open has taken long enough that the row should show progress.
    package static func isOverdue(elapsed: TimeInterval) -> Bool { elapsed >= delay }
}
