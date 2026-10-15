import SwiftUI
import Combine
import AVFoundation
import MediaPlayer
import PlayawayCore
import os

/// One open playlist: its songs, its player, and saving after every change.
@MainActor
final class PlaylistSession: ObservableObject {
    private(set) var url: URL
    @Published private(set) var playlist: Playlist
    @Published private(set) var notice: String?
    let player: PlaylistPlayer
    private let library: PlaylistLibrary
    private var cancellables = Set<AnyCancellable>()

    init(url: URL, playlist: Playlist, library: PlaylistLibrary, model: AppModel) {
        self.url = url
        self.playlist = playlist
        self.library = library
        var provider: () -> Playlist = { playlist }
        let box = Box()
        provider = { box.session?.playlist ?? playlist }
        player = PlaylistPlayer(playlist: provider, settings: model.settings, engine: model.engine,
                                marks: model.marks, registry: model.registry)
        box.session = self
        player.changes.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
    }
    private final class Box { weak var session: PlaylistSession? }

    var name: String { url.deletingPathExtension().lastPathComponent }

    /// The playlist now lives at a new place, for example after its unsaved songs were saved to a file.
    func rebase(to newURL: URL) {
        _ = newURL.startAccessingSecurityScopedResource()
        url = newURL
        objectWillChange.send()
    }

    func add(_ urls: [URL]) {
        let result = adding(urls, to: playlist, classifier: FormatClassifier())
        if !result.rejected.isEmpty { notice = "Some files could not be added: they are not supported audio." }
        replace(result.playlist)
    }

    func remove(at offsets: IndexSet) {
        var updated = playlist
        for index in offsets.sorted(by: >) { if let next = try? removing(at: index, from: updated) { updated = next } }
        replace(updated)
    }

    func move(from source: Int, to destination: Int) {
        if let updated = try? moving(from: source, to: destination, in: playlist) { replace(updated) }
    }

    func dismissNotice() { notice = nil }

    func play(_ track: Track) { if let model { model.requestPlay(track, in: self) } else { player.play(track: track) } }
    func start() { model?.becameActive(self); player.start() }
    weak var model: AppModel?

    private func replace(_ updated: Playlist) {
        playlist = updated
        if case .writeFailed = library.save(updated, to: url) { notice = "The playlist could not be saved." }
    }
}

/// Lets the shared open path (the same one the Mac uses) hand playlists to the app and show its notices. Calls come
/// from the system's open-URL event on the main thread.
final class OpenAdapter: PlaylistOpening, NoticePresenting {
    weak var model: AppModel?
    func canOpen(_ url: URL) -> Bool { url.pathExtension == playlistFileExtension }
    func open(_ url: URL) { MainActor.assumeIsolated { model?.openExternal(url) } }
    func endActivePlayback() { MainActor.assumeIsolated { model?.endActiveSession() } }
    func show(_ notice: Notice) { MainActor.assumeIsolated { model?.failureMessage = notice.title } }
}

@MainActor
final class AppModel: ObservableObject {
    let library: PlaylistLibrary
    /// The shared Playaway folder in iCloud Drive, once the system has told us where it is.
    private(set) var cloudLibrary: PlaylistLibrary?
    private let cloudMover: CloudMoving
    @Published var syncTarget: PlaylistEntry?
    private static let cloudFolderKey = "cloudFolderPath"
    private static let cloudContainer = "iCloud.software.away.play"
    let settings = PlayModeSettings()
    let engine = AVPlaybackEngine()
    let registry = ActiveSessionRegistry()
    let marks = ReadabilityMarkStore()
    let transport: TransportViewModel
    @Published private(set) var entries: [PlaylistEntry] = []
    @Published var cardOpen = false
    @Published var path: [URL] = []
    /// Where the last launch left off, shown paused until the person presses play.
    @Published private(set) var resumePoint: ResumePoint?
    private let memoryStore = ListeningMemoryStore()
    private let openAdapter = OpenAdapter()
    private(set) lazy var cloud: CloudSongs = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PlayawayFakeCloud") {
            return CloudSongs(scripted: ["Demo Two": .succeeds(after: 2), "Demo Three": .fails(after: 5)])
        }
        #endif
        return CloudSongs()
    }()
    private(set) lazy var downloads = DownloadOnPlayCoordinator(downloader: cloud, player: self)
    private var pendingPlays: [SongID: (session: PlaylistSession, track: Track)] = [:]
    @Published private(set) var cloudRevision = 0
    private(set) lazy var openCoordinator = OpenCoordinator(classifier: FormatClassifier(), engine: engine,
                                                            notices: openAdapter, playlists: openAdapter)
    private let launchTimer: LaunchTimer?
    private let launchStore = LaunchReportStore()
    private var firstScreenReported = false
    private var refreshGeneration = 0
    private var lastPositionSave: Date?
    private(set) lazy var scrubber = ScrubDebouncer { [weak self] seconds in try? self?.transport.seek(toSeconds: seconds) }
    @Published private(set) var activeSession: PlaylistSession?
    @Published private(set) var metadata: TrackMetadata?
    private var metadataURL: URL?
    private let nowPlaying = NowPlayingCenter()
    private var sessions: [URL: PlaylistSession] = [:]
    private var cancellables = Set<AnyCancellable>()

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        library = PlaylistLibrary(folder: documents)
        #if DEBUG
        let fakeCloud = ProcessInfo.processInfo.arguments.contains("-PlayawayFakeCloud")
        #else
        let fakeCloud = false
        #endif
        cloudMover = fakeCloud ? PlainFileMover() : UbiquitousMover()
        if fakeCloud {
            let fake = documents.appendingPathComponent("FakeICloud")
            if ProcessInfo.processInfo.arguments.contains("-PlayawaySeedDemo"),
               !ProcessInfo.processInfo.arguments.contains("-PlayawayKeepMemory") { try? FileManager.default.removeItem(at: fake) }
            try? FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
            cloudLibrary = PlaylistLibrary(folder: fake, layout: .folderPerPlaylist)
        } else if let cached = UserDefaults.standard.string(forKey: Self.cloudFolderKey),
                  FileManager.default.fileExists(atPath: cached) {
            cloudLibrary = PlaylistLibrary(folder: URL(fileURLWithPath: cached), layout: .folderPerPlaylist)
        }
        let now = Date()
        if let start = LaunchFacts.processStart(), let boot = LaunchFacts.deviceBoot() {
            launchTimer = LaunchTimer(processStart: start, kind: launchKind(previousLaunch: launchStore.lastLaunch, deviceBoot: boot))
        } else { launchTimer = nil }
        launchStore.noteLaunch(at: now)
        transport = TransportViewModel(engine: engine, registry: registry)
        transport.activePlayerProvider = { [weak self] in self?.activeSession?.player }
        configureAudioSession()
        nowPlaying.attach(model: self)
        // Views read transport and settings through the model, so their changes must reach the model's observers.
        transport.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        engine.events.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.engineChanged() }.store(in: &cancellables)
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-PlayawaySeedDemo") {
            if !arguments.contains("-PlayawayKeepMemory") { memoryStore.save(.empty) }
            seedDemoPlaylist(in: documents, keepExisting: arguments.contains("-PlayawayKeepMemory"))
        }
        #endif
        openAdapter.model = self
        if !fakeCloud { resolveICloud() }
        cloud.onEvent = { [weak self] event in
            guard let self else { return }
            self.downloads.handle(event)
            self.cloudRevision += 1
        }
        refresh()
        transport.startHandler = { [weak self] in
            guard let self else { return false }
            if self.downloads.transportPlay() == .ignored { return true }     // a song is still downloading
            return self.resumeFromMemory()
        }
        restoreMemory()
        $path.dropFirst().sink { [weak self] _ in self?.saveMemory(force: true) }.store(in: &cancellables)
        transport.$position.sink { [weak self] _ in self?.saveMemory(force: false) }.store(in: &cancellables)
    }

    // MARK: Remembering what was playing

    private func restoreMemory() {
        let existing = Set(entries.map { $0.url.lastPathComponent })
        let memory = memoryStore.load().restoring(existingPlaylists: existing) { [self] name, id in
            let url = playlistURL(forFileName: name)
            if case .loaded(let playlist) = library(for: url).load(url) { return playlist.track(withID: id) != nil }
            return false
        }
        path = memory.openPlaylists.map { playlistURL(forFileName: $0) }
        guard let point = memory.nowPlaying else { return }
        let url = playlistURL(forFileName: point.playlistFileName)
        guard let session = session(for: url), let track = session.playlist.track(withID: point.trackID),
              case .resolved(let file) = TrackResolver().resolve(track.reference).0 else { return }
        activeSession = session
        resumePoint = point
        metadataURL = file
        metadata = TrackMetadata.fallback(for: file)
        Task { [weak self] in
            let loaded = await loadTrackMetadata(for: file)
            await MainActor.run { if self?.metadataURL == file { self?.metadata = loaded } }
        }
    }

    /// Play pressed with nothing loaded: carries on from the remembered song and place.
    private func resumeFromMemory() -> Bool {
        guard let point = resumePoint, let session = activeSession,
              let track = session.playlist.track(withID: point.trackID) else { return false }
        resumePoint = nil
        session.model = self
        session.player.resume(track: track, atSeconds: point.positionSeconds)
        return engine.state != .idle
    }

    /// Writes what the next launch needs. Position ticks are throttled; every other change passes `force`.
    func saveMemory(force: Bool) {
        if !force {
            guard engine.state == .playing, shouldSavePosition(lastSaved: lastPositionSave, now: Date()) else { return }
        }
        lastPositionSave = Date()
        var nowPlaying = resumePoint
        if engine.state != .idle, let session = activeSession, let track = session.player.current {
            nowPlaying = ResumePoint(playlistFileName: session.url.lastPathComponent, trackID: track.id,
                                     positionSeconds: engine.position)
        }
        memoryStore.save(ListeningMemory(openPlaylists: path.map { $0.lastPathComponent }, nowPlaying: nowPlaying))
    }

    #if DEBUG
    /// Test aid: a playlist of two short generated tones, so UI tests can play real files.
    private func seedDemoPlaylist(in folder: URL, keepExisting: Bool) {
        func tone(_ seconds: Int, hz: Double) -> Data {
            let rate = 8000, samples = rate * seconds
            var d = Data()
            func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
            func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
            d.append("RIFF".data(using: .ascii)!); u32(36 + samples * 2); d.append("WAVEfmt ".data(using: .ascii)!)
            u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
            d.append("data".data(using: .ascii)!); u32(samples * 2)
            for i in 0..<samples { var v = Int16(sin(2 * .pi * hz * Double(i) / Double(rate)) * 8000).littleEndian; d.append(Data(bytes: &v, count: 2)) }
            return d
        }
        var urls: [URL] = []
        for (name, hz) in [("Demo One", 440.0), ("Demo Two", 520.0), ("Demo Three", 600.0), ("Demo Four", 680.0), ("Demo Five", 760.0)] {
            let url = folder.appendingPathComponent("\(name).wav")
            if !FileManager.default.fileExists(atPath: url.path) { try? tone(60, hz: hz).write(to: url) }
            urls.append(url)
        }
        // Start every seeded launch from the same playlist, whatever earlier tests changed, unless a test is checking
        // what a second launch remembers.
        if keepExisting, FileManager.default.fileExists(atPath: folder.appendingPathComponent("Demo.\(playlistFileExtension)").path) { return }
        if let leftovers = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for file in leftovers where file.pathExtension == playlistFileExtension { try? FileManager.default.removeItem(at: file) }
        }
        guard let playlistURL = try? library.create(named: "Demo") else { return }
        // A list longer than the screen, so tests can scroll to the last song.
        let repeats = ProcessInfo.processInfo.arguments.contains("-PlayawayLongList") ? 6 : 1
        let result = adding(Array(repeating: urls, count: repeats).flatMap { $0 }, to: Playlist(), classifier: FormatClassifier())
        _ = library.save(result.playlist, to: playlistURL)
    }
    #endif

    /// Called by a playlist session whenever its player starts something, so the card knows the playlist.
    func becameActive(_ session: PlaylistSession) { activeSession = session }

    private func engineChanged() {
        let url = engine.currentURL
        if engine.state != .idle { resumePoint = nil }
        saveMemory(force: engine.state != .playing || url != metadataURL)
        if url != metadataURL {
            metadataURL = url
            metadata = url.map { TrackMetadata.fallback(for: $0) }
            if let url { Task { [weak self] in
                let loaded = await loadTrackMetadata(for: url)
                await MainActor.run { if self?.metadataURL == url { self?.metadata = loaded; self?.nowPlaying.update() } }
            } }
        }
        nowPlaying.update()
    }

    /// Going to a playlist is a navigation in the one shared history: going to the one already shown records nothing.
    func openPlaylist(_ url: URL) {
        var history = NavigationHistory<URL>(playlists: path)
        history.navigate(to: .playlist(url))
        path = history.playlistTrail
    }

    /// What the back control says: where it returns to.
    var backTitle: String {
        if case .playlist(let url)? = NavigationHistory<URL>(playlists: path).previous {
            return url.deletingPathExtension().lastPathComponent
        }
        return "Playlists"
    }

    /// A playlist opened from the Files app, in place.
    func openExternal(_ url: URL) {
        guard url.pathExtension == playlistFileExtension else { return }
        _ = url.startAccessingSecurityScopedResource()
        if session(for: url) == nil { failureMessage = "That playlist can't be opened. It may be damaged or made by a newer version of Playaway." }
        else { openPlaylist(url) }
    }

    // MARK: The playlist link on the player card

    @Published var showUnsavedOffer = false
    /// The floating controller's real height, which grows with the text size, so lists leave the right room.
    @Published var playerBarHeight: CGFloat = PlayerBar.height
    var playerBarInset: CGFloat { playerBarVisible ? PlayerBar.inset(forHeight: playerBarHeight) : 0 }
    /// True while the floating controller is on screen, so screens leave room for it.
    var playerBarVisible: Bool { transport.state != .idle || resumePoint != nil }
    @Published var failureMessage: String?

    func availability(of session: PlaylistSession) -> PlaylistAvailability {
        FileManager.default.fileExists(atPath: session.url.path) ? .available : .deleted
    }

    func playlistLinkTapped() {
        guard let session = activeSession else { return }
        switch linkAction(for: availability(of: session)) {
        case .navigate: cardOpen = false; openPlaylist(session.url)
        case .offerSave: showUnsavedOffer = true
        case .noLink: break
        }
    }

    /// Offers the Files save sheet for a playlist whose file is gone, and keeps it unsaved unless a file is written.
    func saveUnsavedPlaylist() {
        guard let session = activeSession else { return }
        Task { @MainActor [weak self] in
            let result = await PlayawayCore.saveUnsavedPlaylist(session.playlist, suggestedName: session.name, using: FilesSaveSheet())
            guard let self else { return }
            switch result {
            case .saved(let newURL):
                let old = session.url
                self.sessions[old] = nil
                session.rebase(to: newURL)
                self.sessions[newURL] = session
                self.path = self.path.map { $0 == old ? newURL : $0 }
            case .cancelled: break
            case .failed: self.failureMessage = "The playlist could not be saved."
            }
        }
    }

    /// Shows the playlist names at once, then fills in counts and notes without blocking the screen or reordering rows.
    func refresh() {
        if entries.isEmpty { entries = Self.combined(library.quickEntries(), cloudLibrary?.quickEntries() ?? []) }
        refreshGeneration += 1
        let generation = refreshGeneration
        let library = self.library
        let cloudLibrary = self.cloudLibrary
        Task.detached(priority: .userInitiated) { [weak self] in
            let full = Self.combined(library.entries(), cloudLibrary?.entries() ?? [])
            await MainActor.run { if let self, self.refreshGeneration == generation { self.entries = full } }
        }
    }

    nonisolated private static func combined(_ phone: [PlaylistEntry], _ cloud: [PlaylistEntry]) -> [PlaylistEntry] {
        (phone + cloud).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func allEntries() -> [PlaylistEntry] { Self.combined(library.entries(), cloudLibrary?.entries() ?? []) }

    /// The library that holds a playlist file, by where the file is.
    func library(for url: URL) -> PlaylistLibrary {
        if let cloudLibrary, url.path.hasPrefix(cloudLibrary.folder.path) { return cloudLibrary }
        return library
    }

    /// A remembered playlist is found by its file name among the playlists in both places.
    private func playlistURL(forFileName name: String) -> URL {
        entries.first { $0.url.lastPathComponent == name }?.url ?? library.folder.appendingPathComponent(name)
    }

    /// Asks the system where the shared iCloud folder is. The first answer can take a moment, so it is asked off the
    /// main thread, and the answer is remembered so the next launch has it at once.
    private func resolveICloud() {
        Task.detached(priority: .utility) { [weak self] in
            let base = FileManager.default.url(forUbiquityContainerIdentifier: Self.cloudContainer)
            await MainActor.run { self?.attachCloud(base) }
        }
    }

    private func attachCloud(_ base: URL?) {
        guard let base else { return }
        let documents = base.appendingPathComponent("Documents")
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        UserDefaults.standard.set(documents.path, forKey: Self.cloudFolderKey)
        guard cloudLibrary?.folder.path != documents.path else { return }
        cloudLibrary = PlaylistLibrary(folder: documents, layout: .folderPerPlaylist)
        cloudRevision += 1     // where the Playaway folder is decides which songs count as in iCloud
        entries = []
        refresh()
    }

    /// Called once when the Playlists screen first appears: records how long the launch took.
    func firstScreenShown() {
        guard !firstScreenReported, let launchTimer else { return }
        firstScreenReported = true
        let report = launchTimer.firstScreenShown(at: Date())
        launchStore.add(report)
        Logger(subsystem: "software.away.play", category: "launch")
            .info("launch \(report.kind.rawValue) \(report.seconds, format: .fixed(precision: 3)) s")
    }

    // MARK: Download on play

    /// A song was chosen. If its file is in iCloud and not on this device it is downloaded first and plays when it
    /// has arrived; otherwise it plays at once.
    func requestPlay(_ track: Track, in session: PlaylistSession) {
        guard case .resolved(let url) = TrackResolver().resolve(track.reference).0 else {
            becameActive(session); session.player.play(track: track); return
        }
        let song = cloud.id(for: url)
        pendingPlays[song] = (session, track)
        downloads.request(song, source: .list, isOnDevice: cloud.presence(of: url, playawayFolder: cloudLibrary?.folder).isOnDevice)
        cloudRevision += 1
    }

    func startPlayback(of song: SongID) {
        guard let pending = pendingPlays[song] else { return }
        becameActive(pending.session)
        pending.session.player.play(track: pending.track)
        cloudRevision += 1
    }

    /// What a song row shows about iCloud, nil when no iCloud account is available.
    /// A song's file address, found once and remembered: resolving a bookmark touches the file system, and doing it for
    /// every row on every update made scrolling jerky.
    private var songURLs: [UUID: URL] = [:]
    private func songURL(for track: Track) -> URL? {
        if let cached = songURLs[track.id] { return cached }
        guard case .resolved(let url) = TrackResolver().resolve(track.reference).0 else { return nil }
        songURLs[track.id] = url
        return url
    }

    func cloudDisplay(for track: Track) -> SongRowCloudDisplay? {
        guard let url = songURL(for: track) else { return nil }
        let song = cloud.id(for: url)
        let tracked = downloads.state(of: song)
        return SongRowCloudDisplay(presence: cloud.presence(of: url, playawayFolder: cloudLibrary?.folder), tracked: tracked == .onThisDevice ? nil : tracked)
    }

    func cloudIconTapped(_ track: Track, session: PlaylistSession) {
        guard let display = cloudDisplay(for: track), let url = songURL(for: track) else { return }
        let song = cloud.id(for: url)
        pendingPlays[song] = (session, track)
        switch cloudIconTapAction(state: display.icon, kind: .song) {
        case .cancelDownload: downloads.cancel(song)
        case .retryDownload: downloads.retry(song)
        case .openSyncDialog, .none, .cancelSync: break    // the sync dialog belongs to the iCloud sync stories
        }
        cloudRevision += 1
    }

    // MARK: Move a playlist to iCloud

    /// The sync dialog for a playlist that is on this phone. If iCloud cannot be reached the person is told why.
    func beginSync(_ entry: PlaylistEntry) {
        guard cloudLibrary != nil else {
            // Two different causes, so say which: no iCloud account or iCloud Drive off, or an account that Playaway
            // still cannot reach its own folder through.
            if FileManager.default.ubiquityIdentityToken == nil {
                failureMessage = "iCloud isn't available: this iPhone is not signed in to iCloud, or iCloud Drive is off. Playlists stay on this iPhone."
            } else {
                failureMessage = "Playaway can't reach its iCloud folder yet, although iCloud is signed in. Playlists stay on this iPhone. Please tell the developer."
            }
            return
        }
        syncTarget = entry
    }

    /// Moves the playlist file into the shared Playaway folder in iCloud Drive. Moving is the one thing that changes
    /// where files live; songs are never moved by this.
    func confirmSync() {
        guard let entry = syncTarget, let cloudLibrary else { return }
        syncTarget = nil
        let mover = cloudMover
        Task { @MainActor [weak self] in
            let result = await Task.detached { Result { try cloudLibrary.adopt(entry.url, using: mover) } }.value
            guard let self else { return }
            switch result {
            case .success(let newURL):
                self.rekey(from: entry.url, to: newURL)
                self.entries = self.allEntries()
                self.saveMemory(force: true)
                UIAccessibility.post(notification: .announcement, argument: "\(entry.name) moved to iCloud")
            case .failure(let error):
                if case LibraryError.alreadyExists = error {
                    self.failureMessage = "A playlist named “\(entry.name)” is already in the Playaway folder in iCloud. Nothing was moved."
                } else {
                    self.failureMessage = "The playlist could not be moved to iCloud. It is still on this iPhone."
                }
            }
        }
    }

    /// Every place that knows a playlist by its file follows it to its new file.
    private func rekey(from old: URL, to new: URL) {
        songURLs.removeAll()
        if let session = sessions.removeValue(forKey: old) { session.rebase(to: new); sessions[new] = session }
        path = path.map { $0 == old ? new : $0 }
        if var point = resumePoint, point.playlistFileName == old.lastPathComponent {
            point.playlistFileName = new.lastPathComponent
            resumePoint = point
        }
    }

    // MARK: Rename and delete

    @Published var renameTarget: URL?
    @Published var renameText = ""
    @Published var renameMessage: String?
    @Published var renameShown = false
    @Published var deleteTarget: PlaylistEntry?

    func beginRename(_ url: URL) {
        renameText = url.deletingPathExtension().lastPathComponent
        renameMessage = nil
        renameTarget = url
        renameShown = true
    }

    /// A refused rename keeps the form open and says why.
    private func reshowRename(_ message: String) {
        renameMessage = message
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    func cancelRename() {
        renameShown = false
        renameTarget = nil
        renameMessage = nil
    }

    /// Renames the playlist and makes every screen, the navigation and the player follow the new file.
    func confirmRename() {
        guard let url = renameTarget else { return }
        do {
            let newURL = try library(for: url).rename(url, to: renameText)
            cancelRename()
            guard newURL != url else { return }
            rekey(from: url, to: newURL)
            entries = allEntries()
            saveMemory(force: true)
            UIAccessibility.post(notification: .announcement, argument: "Renamed to \(newURL.deletingPathExtension().lastPathComponent)")
        } catch let error as LibraryError {
            switch error {
            case .nameEmpty: reshowRename("Enter a name for the playlist.")
            case .invalidCharacters: reshowRename("A playlist name can't contain / or :.")
            case .alreadyExists: reshowRename("A playlist with that name already exists.")
            case .writeFailed, .notAPlaylist: reshowRename("The playlist could not be renamed. Its name has not changed.")
            }
        } catch {
            reshowRename("The playlist could not be renamed. Its name has not changed.")
        }
    }

    /// Deletes the playlist file only. If it was the playlist playing, playback stops and the player closes; if it was
    /// open, the app returns to the Playlists screen.
    func confirmDelete() {
        guard let entry = deleteTarget else { return }
        deleteTarget = nil
        do {
            try library(for: entry.url).delete(entry.url)
        } catch {
            failureMessage = "The playlist could not be deleted. It is still in the list."
            return
        }
        let wasPlaying = activeSession?.url == entry.url
        sessions[entry.url] = nil
        path.removeAll { $0 == entry.url }
        if wasPlaying {
            engine.stop()
            cardOpen = false
            endActiveSession()
        }
        if resumePoint?.playlistFileName == entry.url.lastPathComponent { resumePoint = nil }
        entries = allEntries()
        saveMemory(force: true)
        UIAccessibility.post(notification: .announcement, argument: "Playlist deleted")
    }

    /// A song or playlist opened from outside replaces the playlist that was playing.
    func endActiveSession() {
        activeSession?.player.end()
        activeSession = nil
        resumePoint = nil
    }

    func createPlaylist(named name: String) throws -> URL {
        let url = try (cloudLibrary ?? library).create(named: name)
        entries = allEntries()
        refresh()
        return url
    }

    func session(for url: URL) -> PlaylistSession? {
        if let existing = sessions[url] { return existing }
        let owner = library(for: url)
        guard case .loaded(let playlist) = owner.load(url) else { return nil }
        let session = PlaylistSession(url: url, playlist: playlist, library: owner, model: self)
        session.model = self
        sessions[url] = session
        session.objectWillChange.sink { [weak self] in self?.objectWillChange.send(); self?.refresh() }.store(in: &cancellables)
        return session
    }

    private func configureAudioSession() {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .default)
        try? audio.setActive(true)
    }
}


extension AppModel: SongPlaybackStarting {}


/// Hands a playlist file to the system so it lives in iCloud Drive and syncs to the person's other devices.
struct UbiquitousMover: CloudMoving {
    func moveIntoCloud(_ source: URL, to destination: URL) throws {
        try FileManager.default.setUbiquitous(true, itemAt: source, destinationURL: destination)
    }
}
