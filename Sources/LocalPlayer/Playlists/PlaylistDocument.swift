import PlayawayCore
import AppKit
import Combine

/// One playlist: an ordinary document with its own window, saved where the person chose and autosaved in place.
@objc(PlaylistDocument)
@MainActor
final class PlaylistDocument: NSDocument, PlaylistDocumentEditing, TrackResolutionReporting {
    private(set) var playlist = Playlist()
    let statuses = TrackStatusStore()
    private let changeSubject = PassthroughSubject<Void, Never>()
    private var autosavePending = false
    private var resolutionStarted = false
    /// The file-following state (story 39): reloads, rebases and conflict merges are decided in the shared core.
    private(set) var followed: FollowedPlaylist?
    /// What the last write by the platform's own save put in the file, until the save completes and `followed` is told.
    private var lastWritten: Playlist?
    /// When iCloud conflict versions were last merged into this playlist, for the sync window to show.
    private(set) var lastMerge: Date?

    var services: AppServices { AppServices.shared }
    var changes: AnyPublisher<Void, Never> { changeSubject.eraseToAnyPublisher() }

    /// Where the first-save panel starts. Injectable so tests can check it without a real panel.
    var documentsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    lazy var player: PlaylistPlayer = {
        let player = PlaylistPlayer(
            playlist: { [weak self] in self?.playlist ?? Playlist() },
            playlistFolder: { [weak self] in self?.folder },
            settings: services.settings, order: services.shuffleOrder, resolver: services.resolver, gate: services.gate,
            classifier: services.classifier, engine: services.engine, marks: services.marks,
            registry: services.registry, reporter: self)
        // A song in iCloud but not on this Mac is downloaded first and played when it arrives (stories 20 and 31).
        let services = self.services
        player.isOnDevice = { services.cloudSongs.presence(of: $0).isOnDevice }
        player.wantsDownload = { [weak self] track, url in
            guard let self else { return }
            services.requestDownload(of: track, at: url, in: self)
        }
        return player
    }()

    lazy var relinker = MissingTrackRelinker(statuses: statuses, marks: services.marks)
    /// iCloud sync for this playlist: on when its file is in the Playaway folder (story 18).
    lazy var sync = PlaylistSyncController(document: self, services: services)

    /// Where the playlist's file is, nil before its first save. A song another device stored is looked for here by name.
    var folder: URL? { fileURL?.deletingLastPathComponent() }

    // MARK: Document type

    override class var autosavesInPlace: Bool { true }
    override class var readableTypes: [String] { [playlistTypeIdentifier] }
    override class var writableTypes: [String] { [playlistTypeIdentifier] }
    override class func isNativeType(_ type: String) -> Bool { type == playlistTypeIdentifier }
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        playlistFileExtension
    }

    /// The window title is the file name without the playlist extension ("Dinner"), whatever Finder's setting.
    override var displayName: String! {
        get {
            guard let url = fileURL else { return super.displayName }
            return url.deletingPathExtension().lastPathComponent
        }
        set { super.displayName = newValue }
    }

    // MARK: Reading and writing

    /// NSDocument's reading and writing entry points are not declared main-actor, but this document never opts into
    /// reading or writing off the main thread, so they run there; the work is done by the main-actor methods below.
    nonisolated private func onMain<T: Sendable>(_ body: @MainActor (PlaylistDocument) throws -> T) rethrows -> T {
        nonisolated(unsafe) let document = self
        return try MainActor.assumeIsolated { try body(document) }
    }

    override func read(from url: URL, ofType typeName: String) throws {
        try onMain { try $0.readOnMain(from: url) }
    }

    private func readOnMain(from url: URL) throws {
        switch services.store.load(from: url) {
        case .loaded(let loaded):
            playlist = loaded
            followed = makeFollowed(url: url, playlist: loaded)
            resolveConflictsIfAny()
        case .notFound: throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        case .corrupt: throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)
        case .unsupportedVersion: throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError,
                                                userInfo: [NSLocalizedDescriptionKey: "This playlist was made by a newer version of the app."])
        }
    }

    /// The store does the atomic write. A failed save tells the person and keeps the change in memory, so the
    /// next autosave tries again; the last good version on disk is never touched.
    override func write(to url: URL, ofType typeName: String) throws {
        try onMain { try $0.writeOnMain(to: url) }
    }

    private func writeOnMain(to url: URL) throws {
        let result: SaveResult
        if let followed, url.canonicalPath == fileURL?.canonicalPath {
            // Saving in place: a newer file (the other device's) is taken in first, so nothing of theirs is lost.
            followed.edited(playlist)
            result = followed.save()
            DebugTrace.log("document: write in place: \(result) tracks=\(playlist.tracks.count)")
            if followed.playlist != playlist { takeFromFollowed(cleared: false) }
        } else {
            result = services.store.save(playlist, to: url)
            if result == .saved { lastWritten = playlist }      // told to the followed playlist when the save completes
        }
        if case .writeFailed(let reason) = result {
            services.notices.show(.saveFailed(reason))
            throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        }
    }

    // MARK: Following the file (story 39)

    private func makeFollowed(url: URL, playlist: Playlist) -> FollowedPlaylist? {
        guard let files = services.store as? PlaylistFileReading else { return nil }   // a test store that cannot fingerprint
        return FollowedPlaylist(url: url, playlist: playlist, fingerprint: files.fingerprint(of: url), files: files,
                                conflicts: services.conflictVersions,
                                isInContainer: { CloudFolder.relativePath(inContainer: $0.lastKnownPath) != nil })
    }

    /// The file was moved by this app (turning sync on): same contents, new place.
    func fileMoved(to url: URL) {
        followed = followed?.movedTo(url)
    }

    /// A document made here starts following its file from its first save, as one opened from a file does from its
    /// read: a playlist made with New Playlist, synced and left open must take in the other device's changes too.
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if error == nil, let self {
                if self.followed == nil, let fileURL = self.fileURL {
                    self.followed = self.makeFollowed(url: fileURL, playlist: self.playlist)
                } else if let written = self.lastWritten {
                    self.followed?.wrote(written)           // the file holds what we wrote: it is not an unsaved edit any more
                }
            }
            self?.lastWritten = nil
            completionHandler(error)
        }
    }

    /// NSDocument is a file presenter; the system tells it here when something else wrote, moved or deleted its file.
    override func presentedItemDidChange() {
        DispatchQueue.main.async { [weak self] in self?.fileChangedUnderUs() }
    }

    private func fileChangedUnderUs() {
        guard let followed else { DebugTrace.log("document: file changed under us, not followed"); return }
        followed.edited(playlist)
        let change = followed.fileChanged()
        DebugTrace.log("document: file changed under us: \(change); edited=\(isDocumentEdited) tracks=\(followed.playlist.tracks.count)")
        switch change {
        case .replaced: takeFromFollowed(cleared: true)
        case .merged: takeFromFollowed(cleared: false)
        case .unchanged, .gone, .unreadable: break
        }
        resolveConflictsIfAny()
    }

    override func autosave(withImplicitCancellability implicitlyCancellable: Bool, completionHandler: @escaping (Error?) -> Void) {
        DebugTrace.log("document: autosave begins; edited=\(isDocumentEdited) fileDate=\(fileModificationDate.map { "\($0.timeIntervalSince1970)" } ?? "nil")")
        super.autosave(withImplicitCancellability: implicitlyCancellable) { error in
            DebugTrace.log("document: autosave ended: \(error.map { "\($0)" } ?? "ok")")
            completionHandler(error)
        }
    }

    private func resolveConflictsIfAny() {
        guard let followed else { return }
        followed.edited(playlist)
        if followed.resolveConflicts() == .merged {
            lastMerge = Date()
            takeFromFollowed(cleared: true)
        }
    }

    /// Shows what the followed playlist now holds. `cleared` means the file and the screen agree (nothing of ours is
    /// unsaved); otherwise our edit sits on top and the next autosave writes the merge.
    private func takeFromFollowed(cleared: Bool) {
        guard let followed else { return }
        if cleared {
            playlist = followed.playlist
            updateChangeCount(.changeCleared)
            changeSubject.send()
        } else {
            replacePlaylist(followed.playlist)
        }
        if let modified = followed.fingerprint?.modified { fileModificationDate = modified }
        statuses.setAll([:])
        resolveStatuses()
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.directoryURL = documentsDirectory
        savePanel.allowedContentTypes = []
        savePanel.allowsOtherFileTypes = false
        savePanel.isExtensionHidden = false
        return true
    }

    // MARK: Windows

    override func makeWindowControllers() {
        addWindowController(PlaylistWindowController(document: self))
        startResolutionIfLaunched()
    }

    /// Closing the window of a playlist that is playing stops it. Anything else playing is left alone.
    override func close() {
        if player.isSessionActive { services.engine.stop() }
        super.close()
    }

    // MARK: Editing (the one path windows, menus and scripts use)

    private func replacePlaylist(_ updated: Playlist, actionName: String? = nil) {
        guard updated != playlist else { return }
        let previous = playlist
        undoManager?.registerUndo(withTarget: self) { document in document.restore(previous, actionName: actionName) }
        if let actionName { undoManager?.setActionName(actionName) }
        playlist = updated
        playlistDidChange()
    }

    /// Undo and redo of an edit: put an earlier list of tracks back (which registers the inverse). Track ids are
    /// kept, so statuses and hazard marks stay attached to the right rows. A reference refreshed or located since
    /// the edit is not an edit that can be undone here, so tracks present now keep their current reference.
    private func restore(_ earlier: Playlist, actionName: String?) {
        var restored = earlier
        for index in restored.tracks.indices {
            if let present = playlist.track(withID: restored.tracks[index].id) {
                restored.tracks[index].reference = present.reference
            }
        }
        replacePlaylist(restored, actionName: actionName)
    }

    private func playlistDidChange() {
        updateChangeCount(.changeDone)
        scheduleAutosave()
        changeSubject.send()
    }

    /// Appends supported files in the order given. The first rejected file shows the unsupported notice.
    @discardableResult
    func addFiles(_ urls: [URL]) -> AddResult {
        let result = adding(urls, to: playlist, classifier: services.classifier)
        if let first = result.rejected.first { services.notices.show(.unsupported(first.reason)) }
        for track in result.added {
            if let resolved = services.resolver.resolve(track.reference, besidePlaylistAt: folder).0.resolvedURL {
                statuses.set(.resolved(resolved), for: track.id)
            }
        }
        replacePlaylist(result.playlist, actionName: "Add Files")
        return result
    }

    func removeTracks(at indices: [Int]) throws {
        var updated = playlist
        for index in Set(indices).sorted(by: >) { updated = try removing(at: index, from: updated) }
        replacePlaylist(updated, actionName: "Remove from Playlist")
    }

    func moveTrack(from source: Int, to destination: Int) throws {
        replacePlaylist(try moving(from: source, to: destination, in: playlist), actionName: "Move Track")
    }

    /// Entry point for refreshed and located references. Replaces only that track's reference.
    /// NSDocument's own errors (a file gone at save time, say) go through the app's one notice channel instead of
    /// AppKit's modal alert, so the person gets the house style and a test never blocks on a panel.
    override func presentError(_ error: Error) -> Bool {
        services.notices.show(.saveFailed(error.localizedDescription))
        return false
    }

    override func presentError(_ error: Error, modalFor window: NSWindow, delegate: Any?, didPresent didPresentSelector: Selector?,
                               contextInfo: UnsafeMutableRawPointer?) {
        _ = presentError(error)
    }

    /// Takes the playlist back from the shared intake flow with songs re-pointed at their new files (story 19): the
    /// same rows in the same order, then every row resolved again so it plays from its new place.
    /// Where a track's file is, resolved the way the player resolves it (cloud-relative, then beside the playlist).
    func songURL(for track: Track) -> URL? {
        services.resolver.resolve(track.reference, besidePlaylistAt: folder).0.resolvedURL
    }

    /// Whether a track's file is in iCloud (location only; whether it is downloaded is a separate matter). A file
    /// that cannot be found counts as not in iCloud, as the window draws it.
    /// Why a song cannot be found here, nil when it can (story 42). The Mac never needs a folder permission.
    func unfoundKind(of track: Track) -> UnfoundKind? {
        guard songURL(for: track) == nil else { return nil }
        return classifyUnfound(track.reference, accessNeeded: nil, device: .current)
    }

    func isInICloud(_ track: Track) -> Bool {
        guard let url = songURL(for: track) else { return false }
        return services.cloudSongs.presence(of: url) != .localOnly
    }

    func acceptTransferred(_ updated: Playlist) {
        guard updated.tracks.map(\.id) == playlist.tracks.map(\.id) else { return }
        replacePlaylist(updated, actionName: "Move to iCloud")
        statuses.setAll([:])
        resolveStatuses()
    }

    func apply(_ updatedReference: TrackReference, toTrack id: UUID) {
        guard let index = playlist.index(ofTrackWithID: id), playlist.tracks[index].reference != updatedReference else { return }
        playlist.tracks[index].reference = updatedReference
        playlistDidChange()
    }

    // MARK: Autosave

    /// Autosave in place for saved playlists; several changes in a row are written by one save.
    private func scheduleAutosave() {
        guard fileURL != nil, !autosavePending else { return }
        autosavePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.autosavePending = false
            guard self.fileURL != nil, self.isDocumentEdited else { return }
            self.autosave(withImplicitCancellability: false) { _ in }
        }
    }

    // MARK: Track status

    func trackResolved(id: UUID, status: TrackStatus, reference: TrackReference) {
        statuses.set(status, for: id)
        apply(reference, toTrack: id)
    }

    /// Resolves every track off the main thread, then applies the statuses and any refreshed references. The resolving, and
    /// the rule that drops a result made from a reference that changed meanwhile, are the core's (`PlaylistResolution`).
    func resolveStatuses(completion: (() -> Void)? = nil) {
        let snapshot = playlist.tracks
        let resolver = services.resolver
        let folder = self.folder
        Task { @MainActor [weak self] in
            let results = await PlaylistResolution.resolveInBackground(snapshot, with: resolver, besidePlaylistAt: folder)
            guard let self else { return }
            let current = PlaylistResolution.current(results, in: self.playlist)
            self.statuses.setAll(Dictionary(uniqueKeysWithValues: current.map { ($0.trackID, $0.status) }))
            for entry in current { self.apply(entry.refreshed, toTrack: entry.trackID) }
            completion?()
        }
    }

    private func startResolutionIfLaunched() {
        guard LaunchState.firstWindowPresented, !resolutionStarted else { return }
        resolutionStarted = true
        resolveStatuses()
    }

    /// Called when the first window has been presented, for documents restored at launch.
    func firstWindowPresented() {
        guard !resolutionStarted else { return }
        resolutionStarted = true
        resolveStatuses()
    }

    // MARK: Rename

    enum RenameError: Error, Equatable { case notSaved, nameTaken, invalidName, failed(String) }

    /// Renames the file in place: the tracks and their order are unchanged and the document stays open.
    func renameFile(to newName: String, completion: @escaping (Result<Void, RenameError>) -> Void) {
        guard let current = fileURL else { return completion(.failure(.notSaved)) }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains(":") else { return completion(.failure(.invalidName)) }
        let base = trimmed.hasSuffix(".\(playlistFileExtension)") ? String(trimmed.dropLast(playlistFileExtension.count + 1)) : trimmed
        let target = current.deletingLastPathComponent().appendingPathComponent("\(base).\(playlistFileExtension)")
        guard target != current else { return completion(.success(())) }
        guard !Self.isDifferentExistingFile(target, from: current) else { return completion(.failure(.nameTaken)) }
        move(to: target) { [weak self] error in
            if let error {
                self?.services.notices.show(.saveFailed(error.localizedDescription))
                completion(.failure(.failed(error.localizedDescription)))
            } else {
                completion(.success(()))
            }
        }
    }
}

extension PlaylistDocument {
    /// True when something other than `file` is already at `target`. On a case-insensitive volume a name that
    /// differs only in case is the same file, and renaming to it is allowed.
    fileprivate static func isDifferentExistingFile(_ target: URL, from file: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: target.path) else { return false }
        let identifierKey = URLResourceKey.fileResourceIdentifierKey
        guard let targetID = try? target.resourceValues(forKeys: [identifierKey]).fileResourceIdentifier,
              let fileID = try? file.resourceValues(forKeys: [identifierKey]).fileResourceIdentifier else { return true }
        return !targetID.isEqual(fileID)
    }
}

extension TrackStatus {
    var resolvedURL: URL? {
        if case .resolved(let url) = self { return url }
        return nil
    }
}

/// Process-wide launch facts the document needs without importing the coordinator.
@MainActor
enum LaunchState {
    static var firstWindowPresented = false
}
