import AppKit
import Combine

/// One playlist: an ordinary document with its own window, saved where the person chose and autosaved in place.
@objc(PlaylistDocument)
final class PlaylistDocument: NSDocument, PlaylistDocumentEditing, TrackResolutionReporting {
    private(set) var playlist = Playlist()
    let statuses = TrackStatusStore()
    private let changeSubject = PassthroughSubject<Void, Never>()
    private var autosavePending = false
    private var resolutionStarted = false

    var services: AppServices { AppServices.shared }
    var changes: AnyPublisher<Void, Never> { changeSubject.eraseToAnyPublisher() }

    /// Where the first-save panel starts. Injectable so tests can check it without a real panel.
    var documentsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    lazy var player: PlaylistPlayer = PlaylistPlayer(
        playlist: { [weak self] in self?.playlist ?? Playlist() },
        settings: services.settings, order: services.shuffleOrder, resolver: services.resolver, gate: services.gate,
        classifier: services.classifier, engine: services.engine, marks: services.marks,
        registry: services.registry, reporter: self)

    lazy var relinker = MissingTrackRelinker(statuses: statuses, marks: services.marks)

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

    override func read(from url: URL, ofType typeName: String) throws {
        switch services.store.load(from: url) {
        case .loaded(let loaded): playlist = loaded
        case .notFound: throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        case .corrupt: throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)
        case .unsupportedVersion: throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError,
                                                userInfo: [NSLocalizedDescriptionKey: "This playlist was made by a newer version of the app."])
        }
    }

    /// The store does the atomic write. A failed save tells the person and keeps the change in memory, so the
    /// next autosave tries again; the last good version on disk is never touched.
    override func write(to url: URL, ofType typeName: String) throws {
        if case .writeFailed(let reason) = services.store.save(playlist, to: url) {
            services.notices.show(.saveFailed(reason))
            throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        }
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
            if let resolved = services.resolver.resolve(track.reference).0.resolvedURL {
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

    /// Resolves every track off the main thread, then applies the statuses and any refreshed references.
    func resolveStatuses(completion: (() -> Void)? = nil) {
        let snapshot = playlist.tracks
        let resolver = services.resolver
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let results = snapshot.map { (track: $0, result: resolver.resolve($0.reference)) }
            DispatchQueue.main.async {
                guard let self else { return }
                // A track whose reference changed while this ran (a Locate, say) was resolved from a stale
                // reference: its result is dropped rather than written over the newer state.
                let current = results.filter { self.playlist.track(withID: $0.track.id)?.reference == $0.track.reference }
                self.statuses.setAll(Dictionary(uniqueKeysWithValues: current.map { ($0.track.id, $0.result.0) }))
                for entry in current { self.apply(entry.result.1, toTrack: entry.track.id) }
                completion?()
            }
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
enum LaunchState {
    static var firstWindowPresented = false
}
