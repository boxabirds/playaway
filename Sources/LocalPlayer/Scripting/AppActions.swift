import PlayawayCore
import AppKit

/// The actions a script can ask for, validated and mapped to numbered refusals. Each one ends in the same handler
/// the on-screen control uses (transport view model, playlist document, open coordinator), so a scripted action and
/// its click cannot drift apart.
@MainActor
final class AppActions {
    private static let saveWaitSeconds: TimeInterval = 10
    /// How long a scripted play waits for a download from iCloud before giving up (a proposal; no bound is decided).
    private static let downloadWaitSeconds: TimeInterval = 110
    private static let runLoopStep: TimeInterval = 0.01

    let services: AppServices
    var updater: UpdaterController?
    var isReady: () -> Bool = { LaunchState.firstWindowPresented }
    var defaultSaveDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    init(services: AppServices) {
        self.services = services
    }

    private var controller: PlaylistDocumentController { PlaylistDocumentController.current }
    private var transport: TransportViewModel { services.transport }

    func ready() throws {
        guard isReady() else { throw ScriptFailure.notReady }
    }

    // MARK: Reading state (never changes anything)

    var isPlaying: Bool { services.engine.state == .playing }
    var currentTrackName: String { services.engine.currentURL?.lastPathComponent ?? "" }
    var position: Double { services.engine.position }
    var volumePercent: Int { Int((services.engine.volume * Double(scriptVolumeMax)).rounded()) }
    var isMuted: Bool { services.engine.isMuted }
    var shuffleOn: Bool { services.settings.shuffleOn }
    var repeatName: String { services.settings.repeatMode.rawValue }
    var playlistNames: [String] { controller.playlistDocuments.map { $0.displayName } }

    // MARK: Opening and playback

    func openFile(path: String) throws {
        try ready()
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { throw ScriptFailure.notFound(path) }
        let url = URL(fileURLWithPath: path)
        switch services.openCoordinator.open(url) {
        case .unsupported(let reason): throw ScriptFailure.unsupported(reason)
        case .played(.playing), .playlistHandedOver: break
        case .played(.noOutputDevice): throw ScriptFailure.invalid("No audio output device is available.")
        case .played(.failed(let reason)): throw ScriptFailure.notFound("\(path) (\(reason))")
        }
    }

    func play() throws { try ready(); try mapTransport { try transport.play() } }
    func pause() throws { try ready(); try mapTransport { try transport.pause() } }
    func stop() throws { try ready(); try mapTransport { try transport.stop() } }
    func next() throws { try ready(); try mapTransport { try transport.next() } }
    func previous() throws { try ready(); try mapTransport { try transport.previous() } }
    func seek(toSeconds seconds: Double) throws { try ready(); try mapTransport { try transport.seek(toSeconds: seconds) } }

    func setVolume(percent: Int) throws {
        try ready()
        try mapTransport { try transport.setScriptVolume(percent) }
    }

    func setMuted(_ muted: Bool) throws { try ready(); transport.setMuted(muted) }
    func setShuffle(_ on: Bool) throws { try ready(); services.settings.setShuffle(on) }

    func setRepeat(_ name: String) throws {
        try ready()
        guard let mode = RepeatMode(rawValue: name.lowercased()) else {
            throw ScriptFailure.invalid("Repeat must be off, all or one.")
        }
        services.settings.setRepeat(mode)
    }

    private func mapTransport(_ body: () throws -> Void) throws {
        do { try body() } catch let error as TransportViewModel.ActionError {
            switch error {
            case .nothingPlaying: throw ScriptFailure.nothingPlaying
            case .invalidSeekPosition: throw ScriptFailure.invalid("That position is outside the track.")
            case .invalidVolume: throw ScriptFailure.invalid("Volume must be a whole number from \(scriptVolumeMin) to \(scriptVolumeMax).")
            }
        }
    }

    // MARK: Playlists

    func document(named name: String) throws -> PlaylistDocument {
        guard let document = controller.playlistDocument(named: name) else { throw ScriptFailure.noOpenPlaylist(named: name) }
        return document
    }

    private func track(at position: Int, in document: PlaylistDocument) throws -> Track {
        let tracks = document.playlist.tracks
        guard position >= 1, position <= tracks.count else { throw ScriptFailure.noSuchTrack(position, count: tracks.count) }
        return tracks[position - 1]
    }

    /// Plays a track of an open playlist exactly as a double-click on its row does. A song in iCloud but not on this
    /// Mac starts the same download the window would (story 20) and the command returns once the song is playing,
    /// or with an error if the download failed (story 22).
    func playTrack(_ position: Int, inPlaylist name: String) throws {
        try ready()
        let document = try document(named: name)
        let track = try track(at: position, in: document)
        DebugTrace.log("script play: begin \(track.reference.fileName) session=\(document.player.isSessionActive) current=\(document.player.current?.reference.fileName ?? "nil")")
        document.player.play(track: track)
        DebugTrace.log("script play: after play(track:) session=\(document.player.isSessionActive) current=\(document.player.current?.reference.fileName ?? "nil")")
        let playing = { document.player.isSessionActive && document.player.current == track }
        guard !playing() else { return }
        if let url = document.songURL(for: track) {
            let song = MacSongs.id(for: url)
            if services.downloads.state(of: song).isDownloading {
                waitUntil(seconds: Self.downloadWaitSeconds) { playing() || !self.services.downloads.state(of: song).isDownloading }
                if playing() { return }
                DebugTrace.log("script play: not playing after the wait; state=\(services.downloads.state(of: song)) mark=\(services.marks.mark(of: track)) session=\(document.player.isSessionActive) current=\(document.player.current?.reference.fileName ?? "nil")")
                throw ScriptFailure.downloadFailed(track.reference.fileName)
            }
        }
        if services.marks.mark(of: track) == .unreadable {
            throw ScriptFailure.notFound(track.reference.lastKnownPath)
        }
        throw ScriptFailure.invalid("The track could not be played.")
    }

    /// A new untitled playlist. With a path it is saved there; with only a name, in the default save folder.
    @discardableResult
    func newPlaylist(named name: String?, atPath path: String?) throws -> String {
        try ready()
        var destination: URL?
        if let path, !path.isEmpty {
            destination = URL(fileURLWithPath: path)
        } else if let name, !name.isEmpty {
            destination = defaultSaveDirectory.appendingPathComponent(name)
        }
        if var target = destination {
            if target.pathExtension.lowercased() != playlistFileExtension { target.appendPathExtension(playlistFileExtension) }
            destination = target
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: target.deletingLastPathComponent().path, isDirectory: &isDirectory), isDirectory.boolValue,
                  FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
                throw ScriptFailure.invalid("The playlist cannot be saved to \(target.path).")
            }
            guard !FileManager.default.fileExists(atPath: target.path) else {
                throw ScriptFailure.invalid("A file already exists at \(target.path).")
            }
        }
        let document = try controller.openUntitledDocumentAndDisplay(true) as! PlaylistDocument
        if let target = destination {
            var finished = false
            var failure: Error?
            document.save(to: target, ofType: playlistTypeIdentifier, for: .saveOperation) { error in failure = error; finished = true }
            waitUntil { finished }
            if failure != nil || document.fileURL == nil {
                document.close()
                throw ScriptFailure.invalid("The playlist could not be saved to \(target.path).")
            }
        }
        return document.displayName
    }

    func renamePlaylist(_ name: String, to newName: String) throws {
        try ready()
        let document = try document(named: name)
        var result: Result<Void, PlaylistDocument.RenameError>?
        document.renameFile(to: newName) { result = $0 }
        waitUntil { result != nil }
        switch result {
        case .success: return
        case .failure(.notSaved): throw ScriptFailure.invalid("Save the playlist before renaming it.")
        case .failure(.nameTaken): throw ScriptFailure.invalid("A playlist named \(newName) already exists in that folder.")
        case .failure(.invalidName): throw ScriptFailure.invalid("That is not a valid playlist name.")
        case .failure(.failed(let reason)): throw ScriptFailure.invalid(reason)
        case nil: throw ScriptFailure.invalid("Renaming did not finish.")
        }
    }

    /// Adds a file as the window's Add Files and a drop do (story 21): into a synced playlist the song then goes
    /// through the one shared Files flow with the answer given here ("move to iCloud", "copy to iCloud", "add without
    /// syncing"; none means add without syncing). An answer that would move or copy into iCloud is refused with 1009
    /// while iCloud is unavailable, before anything is added.
    func addTrack(path: String, toPlaylist name: String, files filesAnswer: String? = nil) throws {
        try ready()
        let document = try document(named: name)
        let files = try Self.filesChoice(from: filesAnswer)
        guard FileManager.default.fileExists(atPath: path) else { throw ScriptFailure.notFound(path) }
        if let files, files != .doNothing, services.cloud.availability.root == nil { throw ScriptFailure.iCloudUnavailable }
        let result = document.addFiles([URL(fileURLWithPath: path)])
        if let rejected = result.rejected.first { throw ScriptFailure.unsupported(rejected.reason) }
        var done = false
        Task { @MainActor in
            await document.sync.bringAdded(result.added, presenter: ScriptedFilesPresenter(files))
            done = true
        }
        waitUntil { done }
    }

    /// The Files question's answer as a script gives it. Nil when none was given.
    static func filesChoice(from answer: String?) throws -> FilesChoice? {
        switch answer?.lowercased() {
        case nil: return nil
        case "move", "move to icloud": return .moveToICloud
        case "copy", "copy to icloud": return .copyToICloud
        case "add without syncing": return .doNothing
        default: throw ScriptFailure.invalid("The files answer must be move to iCloud, copy to iCloud or add without syncing.")
        }
    }

    func removeTrack(_ position: Int, fromPlaylist name: String) throws {
        try ready()
        let document = try document(named: name)
        _ = try track(at: position, in: document)
        try document.removeTracks(at: [position - 1])
    }

    func moveTrack(_ from: Int, to destination: Int, inPlaylist name: String) throws {
        try ready()
        let document = try document(named: name)
        _ = try track(at: from, in: document)
        _ = try track(at: destination, in: document)
        try document.moveTrack(from: from - 1, to: destination - 1)
    }

    func locateTrack(_ position: Int, inPlaylist name: String, withFile path: String) throws {
        try ready()
        let document = try document(named: name)
        let track = try track(at: position, in: document)
        switch document.relinker.relink(trackID: track.id, to: URL(fileURLWithPath: path), in: document) {
        case .relinked: return
        case .cancelled: return
        case .notReadable: throw ScriptFailure.locateFailed("The file at \(path) could not be read.")
        case .editRefused: throw ScriptFailure.locateFailed("Track \(position) is not missing, so it cannot be located.")
        }
    }

    // MARK: iCloud sync (story 18)

    /// Turns iCloud sync on for an open playlist, with the Playlist dialog's answer given in advance ("move" or
    /// "don't sync") so no script waits on a sheet. Returns the playlist file's path afterwards. A playlist already
    /// in iCloud needs no answer. Refused with 1009 while iCloud is unavailable, as the window's switch is disabled.
    func syncPlaylist(_ name: String, answering answer: String?, files filesAnswer: String? = nil) throws -> SyncReport {
        try ready()
        let document = try document(named: name)
        guard services.cloud.availability.root != nil else { throw ScriptFailure.iCloudUnavailable }
        if document.sync.state == .on { return SyncReport(path: document.fileURL?.path ?? "", result: TransferResult()) }
        let choice: PlaylistChoice
        switch answer?.lowercased() {
        case "move": choice = .move
        case "don't sync", "don’t sync", "dont sync": choice = .dontSync
        case nil: throw ScriptFailure.invalid("Sync playlist needs an answer for the Playlist question: move or don't sync.")
        default: throw ScriptFailure.invalid("The answer must be move or don't sync.")
        }
        let files = try Self.filesChoice(from: filesAnswer)
        var outcome: PlaylistSyncOutcome?
        Task { @MainActor in
            outcome = await document.sync.turnOn(presenter: ScriptedPlaylistPresenter(choice), filesPresenter: ScriptedFilesPresenter(files))
        }
        waitUntil { outcome != nil }
        switch outcome {
        case .on(let url): return SyncReport(path: url.path, result: document.sync.lastReport)
        case .left: return SyncReport(path: document.fileURL?.path ?? "", result: TransferResult())
        case .failed(let why): throw ScriptFailure.syncFailed(why)
        case .unavailable: throw ScriptFailure.iCloudUnavailable
        case nil: throw ScriptFailure.syncFailed("Syncing did not finish.")
        }
    }

    /// Where each song of an open playlist is: "in iCloud" or "not in iCloud", in row order, as the window shows it.
    /// Reading changes nothing.
    func trackICloudStates(_ name: String) throws -> [String] {
        try ready()
        return try document(named: name).scriptTrackICloudStates
    }

    /// Whether an open playlist has iCloud sync on. Reading changes nothing.
    func isPlaylistSynced(_ name: String) throws -> Bool {
        try ready()
        return try document(named: name).sync.state == .on
    }

    // MARK: Updates

    func checkForUpdates() throws {
        guard let updater, updater.state == .idle else { throw ScriptFailure.notReady }
        updater.checkForUpdates()
    }

    private func waitUntil(seconds: TimeInterval = AppActions.saveWaitSeconds, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(Self.runLoopStep))
        }
    }
}

/// What a scripted sync did, returned to the script as a record: the path of the playlist file afterwards and the
/// counts the on-screen report box shows.
struct SyncReport: Equatable {
    let path: String
    let moved: Int, copied: Int, copiedInstead: Int, failed: Int

    init(path: String, result: TransferResult) {
        self.path = path
        moved = result.moved; copied = result.copied; copiedInstead = result.copiedInstead; failed = result.failures.count
    }

    /// The record's fields, keyed as the scripting dictionary names them.
    var record: [String: Any] {
        ["path": path, "moved": moved, "copied": copied, "copiedInstead": copiedInstead, "failed": failed]
    }
}
