import SwiftUI
import PlayawayCore

// Restoring access to songs outside the app, and offering the whole folder when a song is added (stories 41 and 42).
extension AppModel {
    // MARK: Restoring access (story 41)

    /// What this playlist needs on this device: the songs that cannot be found and whose folder this device may not read,
    /// the plan to ask for those folders, and which songs show the locked cloud. A folder in which some song of the
    /// playlist IS found is never asked for. Kept until something that could change the answer changes.
    func accessSnapshot(for session: PlaylistSession) -> AccessSnapshot {
        if let cached = accessCache[session.url], cached.revision == cloudRevision { return cached.snapshot }
        let folder = session.folder
        var unfound: [UnfoundSong] = [], found: [CloudPath] = []
        for track in session.playlist.tracks {
            guard let location = track.reference.portableLocation, location.isInDrive else { continue }
            if resolver.accessNeeded(for: track.reference, besidePlaylistAt: folder) != nil {
                unfound.append(UnfoundSong(id: track.id, location: location, fileName: track.reference.fileName, fileSize: track.reference.fileSize))
            } else if case .resolved = resolver.resolve(track.reference, besidePlaylistAt: folder).0, !roots.reaches(location) {
                found.append(location)      // found by its own means, not through a permission given here: the folder is readable
            }
        }
        let plan = RecoveryPlanner.plan(unfound: unfound.map(\.location), found: found)
        let planned = Set(plan?.folders.map(\.name) ?? [])
        let needing = unfound.filter { planned.contains($0.location.topFolder ?? "") }
        let snapshot = AccessSnapshot(plan: plan, unfound: needing, locked: Set(needing.map(\.id)))
        accessCache[session.url] = (cloudRevision, snapshot)
        return snapshot
    }

    /// Why a song cannot be found on this device, nil when it can (story 42, with the locked cloud of story 41).
    func unfoundKind(for track: Track, in session: PlaylistSession) -> UnfoundKind? {
        guard songURL(for: track, in: session) == nil else { return nil }
        return classifyUnfound(track.reference, accessNeeded: needsAccess(track, in: session) ? "locked" : nil, device: .current)
    }

    func recoveryPlan(for session: PlaylistSession) -> RecoveryPlan? { accessSnapshot(for: session).plan }
    func needsAccess(_ track: Track, in session: PlaylistSession) -> Bool { accessSnapshot(for: session).locked.contains(track.id) }

    /// Shows the explanation (the banner's Restore, and a tap on a locked cloud).
    func beginRestore(for session: PlaylistSession) {
        guard recoveryPlan(for: session) != nil else { return }
        restoreSession = session
        restorePhase = .explain
        pickingSession = nil
    }

    func cancelRestore() { restoreSession = nil; pickingSession = nil }

    /// The restore sheet went away. While the chooser is up that is how the system answers Open, so the pick stays
    /// pending until the chooser reports; at any other moment it is the person dismissing the explanation.
    func restoreSheetDismissed() {
        if restorePhase == .pick, let session = restoreSession { pickingSession = session; restoreSession = nil }
        else { cancelRestore() }
    }

    /// Where the chooser opens: the folder being asked for, as an iPhone or iPad lays out iCloud Drive.
    var restoreHint: URL? {
        guard let session = restoreSession, let folder = recoveryPlan(for: session)?.folders.first else { return nil }
        return RecoveryPlanner.hint(for: folder)
    }

    /// Continue on the explanation: the system's folder chooser (in the fake drive, the answer a launch argument names).
    func continueRestore() {
        guard let session = restoreSession, let folder = recoveryPlan(for: session)?.folders.first else { restoreSession = nil; return }
        #if DEBUG
        if let fakeDriveRoot, !Self.fakesTheChooserSheet {
            folderPicked(Self.fakePick(in: fakeDriveRoot, default: folder.drivePath))
            return
        }
        #endif
        pickingSession = session
        restorePhase = .pick
    }


    /// The chooser's answer; nil when the person cancelled. The search for the songs runs off the main thread, with a
    /// progress card and a Cancel, then says how many songs came back, or why nothing did.
    func folderPicked(_ url: URL?) {
        guard let session = pickingSession ?? restoreSession else { return }
        pickingSession = nil
        restoreSession = nil
        guard let url else { return }                       // the person cancelled the chooser: nothing to do
        let snapshot = accessSnapshot(for: session)
        _ = url.startAccessingSecurityScopedResource()
        let flag = CancelFlag()
        restoreCancellation = flag
        restoreProgress = RestoreProgress(folder: url.lastPathComponent, looked: 0)
        let roots = self.roots, unfound = snapshot.unfound
        #if DEBUG
        let listing: FolderListing = Self.restoreDelay.map { SlowFolderListing(delay: $0) } ?? SystemFolderListing()
        #else
        let listing: FolderListing = SystemFolderListing()
        #endif
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = RecoveryPlanner.apply(picked: url, unfound: unfound, roots: roots, listing: listing,
                                               progress: { looked in Task { @MainActor in self?.restoreProgress?.looked = looked } },
                                               isCancelled: { flag.isCancelled })
            await MainActor.run { self?.finishRestore(result, cancelled: flag.isCancelled) }
        }
    }

    func cancelRestoreSearch() { restoreCancellation?.cancel() }

    func finishRestore(_ result: RecoveryResult, cancelled: Bool) {
        restoreProgress = nil
        restoreCancellation = nil
        songCache.removeAll()
        pendingPlays.removeAll()
        cloudRevision += 1
        switch result.reason {
        case nil where cancelled:
            enqueueMessage("Restored \(result.restored) of \(result.needed) songs. You cancelled the search, so songs that have moved were not looked for.")
        case nil: enqueueMessage("Restored \(result.restored) of \(result.needed) songs.")
        case .cancelled?: enqueueMessage("Search cancelled. Nothing was restored.")
        case .notInICloudDrive?: enqueueMessage("That folder is not in your iCloud Drive. Choose the folder that holds your songs.")
        case .holdsNoneOfTheSongs?: enqueueMessage("None of the songs were in that folder. Choose the folder that holds them, or a folder above it.")
        }
    }


    /// Locate (long-press on a locked cloud): one song, one file, kept on this device only.
    func beginLocate(_ track: Track, in session: PlaylistSession) {
        locateTarget = (session, track)
        #if DEBUG
        if let fakeDriveRoot, let location = track.reference.portableLocation {
            locate(fakeDriveRoot.appendingPathComponent(location.relativePath)); return
        }
        #endif
        locateShown = true
    }

    func locate(_ file: URL?) {
        locateShown = false
        guard let file, let target = locateTarget, let location = target.track.reference.portableLocation else { return }
        locateTarget = nil
        _ = file.startAccessingSecurityScopedResource()
        guard roots.locate(savedPath: location.relativePath, file: file) else {
            enqueueMessage("That file could not be used for this song."); return
        }
        songCache.removeAll()
        pendingPlays.removeAll()
        cloudRevision += 1
    }

    // MARK: Offering the whole folder when a song is added (story 41)

    var declinedNudges: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.declinedNudgesKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.declinedNudgesKey) }
    }

    /// The folder to offer after songs were added from outside; nil when something covers it, it was already declined,
    /// or the song is in the Playaway folder or at the top of iCloud Drive.
    func nudgeFolder(for added: [Track]) -> String? {
        for track in added {
            guard let location = track.reference.portableLocation, location.isInDrive, let top = location.topFolder else { continue }
            if !roots.covers(location), !declinedNudges.contains(top) { return top }
        }
        return nil
    }

    func considerNudge(after added: [Track]) {
        if let folder = nudgeFolder(for: added) { nudgeFolderName = folder }
    }

    func nudgeAnswered(accepted: Bool) {
        guard let folder = nudgeFolderName else { return }
        nudgeFolderName = nil
        guard accepted else { declinedNudges.insert(folder); return }
        #if DEBUG
        if let fakeDriveRoot {
            if let grant = roots.grant(pickedFolder: fakeDriveRoot.appendingPathComponent(folder, isDirectory: true)) {
                enqueueMessage("Playaway can now use “\(grant.drivePath)” on this device.")
            }
            cloudRevision += 1
            return
        }
        #endif
        nudgePickerShown = true
    }

    func nudgeFolderPicked(_ url: URL?) {
        nudgePickerShown = false
        guard let url else { return }
        _ = url.startAccessingSecurityScopedResource()
        if let grant = roots.grant(pickedFolder: url) { enqueueMessage("Playaway can now use “\(grant.drivePath)” on this device.") }
        else { enqueueMessage("That folder is not in your iCloud Drive.") }
        songCache.removeAll()
        cloudRevision += 1
    }
}
