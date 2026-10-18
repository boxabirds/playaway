import Foundation

/// What a device last saw of a playlist file: enough to tell its own save's echo from another device's change.
package struct FileFingerprint: Equatable {
    package let modified: Date
    package let size: Int
    package init(modified: Date, size: Int) { self.modified = modified; self.size = size }
}

/// The file operations an open playlist needs; the real store plus a fingerprint read.
package protocol PlaylistFileReading {
    func fingerprint(of url: URL) -> FileFingerprint?
    func load(from url: URL) -> LoadResult
    func save(_ playlist: Playlist, to url: URL) -> SaveResult
}

extension PlaylistStore: PlaylistFileReading {
    package func fingerprint(of url: URL) -> FileFingerprint? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return FileFingerprint(modified: modified, size: (attributes[.size] as? NSNumber)?.intValue ?? 0)
    }
}

/// One of iCloud's unresolved versions of a playlist file: where its contents can be read, and when it was made.
package struct ConflictVersion: Equatable {
    package let url: URL
    package let modified: Date
    package init(url: URL, modified: Date) { self.url = url; self.modified = modified }
}

/// How a device learns of iCloud's conflict versions and tells it they are dealt with. The live one wraps
/// NSFileVersion; tests serve version files from a folder.
package protocol ConflictVersionReading {
    func unresolvedVersions(of url: URL) -> [ConflictVersion]
    func markResolved(_ versions: [ConflictVersion], of url: URL)
}

package struct NoConflictVersions: ConflictVersionReading {
    package init() {}
    package func unresolvedVersions(of url: URL) -> [ConflictVersion] { [] }
    package func markResolved(_ versions: [ConflictVersion], of url: URL) {}
}

package enum FileChange: Equatable {
    /// Our own save echoed back, or nothing new: nothing to do.
    case unchanged
    /// No edit of ours was pending: the file's contents are now the playlist.
    case replaced
    /// Our unsaved edit was merged on top of the file's new contents; still unsaved.
    case merged
    /// The file is no longer there.
    case gone
    /// The file could not be read as a playlist; the open playlist is kept and nothing is written.
    case unreadable
}

package enum ConflictOutcome: Equatable {
    case none
    case merged
    case resolvedWithoutChange
    case writeFailed
}

/// An open playlist that follows its file (story 39): it reloads when another device changes the file, merges a
/// pending edit on top instead of losing either side, never writes an older copy over a newer file, and folds
/// iCloud's conflict versions in by song. Shared by the Mac document and the iPhone session, which only forward the
/// file system's "it changed" and the person's edits here.
package final class FollowedPlaylist {
    package let url: URL
    package private(set) var playlist: Playlist
    package private(set) var fingerprint: FileFingerprint?
    /// What the file held when it was last read or written; an edit is a playlist that differs from it.
    private var onDisk: Playlist
    private let files: PlaylistFileReading
    private let conflicts: ConflictVersionReading
    private let isInContainer: (TrackReference) -> Bool

    /// Called when the playlist on screen must change because the file did (replaced or merged).
    package var onReplaced: ((Playlist) -> Void)?
    /// Called when the file is gone; the platform's existing playlist-gone handling takes over.
    package var onGone: (() -> Void)?

    package init(url: URL, playlist: Playlist, fingerprint: FileFingerprint?, files: PlaylistFileReading,
                 conflicts: ConflictVersionReading = NoConflictVersions(), isInContainer: @escaping (TrackReference) -> Bool) {
        self.url = url
        self.playlist = playlist
        self.onDisk = playlist
        self.fingerprint = fingerprint
        self.files = files
        self.conflicts = conflicts
        self.isInContainer = isInContainer
    }

    /// An edit is a change to the list: which songs, in what order, at what paths. A refreshed bookmark for the same
    /// file (the resolver re-points references as it finds them) is not an edit, or a remote change landing a moment
    /// after a resolve would be merged on top of a list the person never touched.
    package var isEdited: Bool { !Self.sameListing(playlist, onDisk) }

    static func sameListing(_ a: Playlist, _ b: Playlist) -> Bool {
        a.tracks.count == b.tracks.count && zip(a.tracks, b.tracks).allSatisfy {
            $0.id == $1.id && $0.reference.lastKnownPath == $1.reference.lastKnownPath && $0.reference.fileName == $1.reference.fileName
        }
    }

    /// An edit made on this device, not yet saved.
    package func edited(_ updated: Playlist) { playlist = updated }

    /// The platform wrote `saved` to the file itself (the Mac's safe-save writes a temporary file and swaps it in, so `save()`
    /// never sees it). The file now holds it. Without this, the next change of the file by another device finds our saved
    /// edit still counted as unsaved, and merges it on top of their later version instead of replacing ours with theirs.
    package func wrote(_ saved: Playlist) {
        onDisk = saved
        fingerprint = files.fingerprint(of: url)
    }

    /// The file was moved by this device (turning sync on); the contents are the same, the place is new.
    package func movedTo(_ newURL: URL) -> FollowedPlaylist {
        let moved = FollowedPlaylist(url: newURL, playlist: playlist, fingerprint: files.fingerprint(of: newURL), files: files,
                                     conflicts: conflicts, isInContainer: isInContainer)
        moved.onDisk = onDisk
        moved.onReplaced = onReplaced
        moved.onGone = onGone
        return moved
    }

    /// The file system says the file changed. Our own save is recognised by its fingerprint and ignored.
    @discardableResult
    package func fileChanged() -> FileChange {
        guard let now = files.fingerprint(of: url) else { onGone?(); return .gone }
        if now == fingerprint { return .unchanged }
        switch files.load(from: url) {
        case .loaded(let theirs):
            fingerprint = now
            let mine = playlist
            let hadEdit = isEdited
            onDisk = theirs
            if mine == theirs { return .unchanged }                 // the same contents (our own save, say): nothing to show
            if !hadEdit {
                playlist = theirs
                onReplaced?(playlist)
                return .replaced
            }
            playlist = mergedPlaylist([version(theirs, at: now), version(mine, at: justAfter(now))], isInContainer: isInContainer)
            onReplaced?(playlist)
            return .merged
        case .notFound:
            onGone?()
            return .gone
        case .corrupt, .unsupportedVersion:
            return .unreadable
        }
    }

    /// Saves our playlist, taking a newer file's contents in first so the other device's work is kept. Writes
    /// nothing when the file already holds the same playlist.
    @discardableResult
    package func save() -> SaveResult {
        let now = files.fingerprint(of: url)
        if let now, now != fingerprint, case .loaded(let theirs) = files.load(from: url), theirs != onDisk {
            playlist = mergedPlaylist([version(theirs, at: now), version(playlist, at: justAfter(now))], isInContainer: isInContainer)
            onDisk = theirs
        }
        guard playlist != onDisk else {
            fingerprint = now ?? fingerprint
            return .saved
        }
        let result = files.save(playlist, to: url)
        if result == .saved {
            onDisk = playlist
            fingerprint = files.fingerprint(of: url)
        }
        return result
    }

    /// Folds iCloud's unresolved conflict versions in: every readable one is merged with ours, the result is written
    /// once if it differs, and the readable versions are marked resolved. A damaged version is left alone.
    @discardableResult
    package func resolveConflicts() -> ConflictOutcome {
        let versions = conflicts.unresolvedVersions(of: url)
        guard !versions.isEmpty else { return .none }
        var readable: [ConflictVersion] = []
        var theirs: [PlaylistVersion] = []
        for version in versions {
            guard case .loaded(let playlist) = files.load(from: version.url) else { continue }
            readable.append(version)
            theirs.append(PlaylistVersion(playlist: playlist, modified: version.modified, bytes: (try? Data(contentsOf: version.url)) ?? Data()))
        }
        guard !readable.isEmpty else { return .none }
        let mine = PlaylistVersion(playlist: playlist, modified: isEdited ? Date() : (fingerprint?.modified ?? Date()),
                                   bytes: isEdited ? Data() : ((try? Data(contentsOf: url)) ?? Data()))
        let merged = mergedPlaylist([mine] + theirs, isInContainer: isInContainer)
        if merged == onDisk, !isEdited {
            conflicts.markResolved(readable, of: url)
            return .resolvedWithoutChange
        }
        guard files.save(merged, to: url) == .saved else { return .writeFailed }
        playlist = merged
        onDisk = merged
        fingerprint = files.fingerprint(of: url)
        conflicts.markResolved(readable, of: url)
        return .merged
    }

    // MARK: Helpers

    private func version(_ playlist: Playlist, at fingerprint: FileFingerprint) -> PlaylistVersion {
        PlaylistVersion(playlist: playlist, modified: fingerprint.modified, bytes: (try? Data(contentsOf: url)) ?? Data())
    }

    /// Our unsaved edit is the latest state the person has, so it is dated just after the file, whatever clock
    /// wrote the file (another device's clock may run ahead of ours).
    private func justAfter(_ fingerprint: FileFingerprint) -> Date {
        max(Date(), fingerprint.modified.addingTimeInterval(0.001))
    }

    private func version(_ playlist: Playlist, at date: Date) -> PlaylistVersion {
        PlaylistVersion(playlist: playlist, modified: date, bytes: Data())
    }
}
