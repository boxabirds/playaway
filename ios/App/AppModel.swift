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
        let before = Set(playlist.tracks.map(\.id))
        let result = adding(urls, to: playlist, classifier: FormatClassifier())
        if !result.rejected.isEmpty { notice = "Some files could not be added: they are not supported audio." }
        replace(result.playlist)
        // Songs added to a playlist in iCloud go through the same Files flow as turning sync on.
        let added = result.playlist.tracks.filter { !before.contains($0.id) }
        if !added.isEmpty { model?.songsEntered(added, in: self, source: .iPhoneAdd) }
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

    /// Takes a playlist changed elsewhere (for example songs moved into iCloud) and saves it.
    func apply(_ updated: Playlist) { replace(updated) }

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

/// Lets the shared Files flow ask its question and show its messages through the app's screens.
final class FilesPresenterAdapter: FilesPromptPresenting {
    weak var model: AppModel?
    func askFilesChoice() async -> FilesChoice { await model?.presentFilesChoice() ?? FilesPrompt.dismissalChoice }
    func show(message: String) async { await MainActor.run { model?.enqueueMessage(message) } }
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
    private let memoryStore = ListeningMemoryStore()
    private let openAdapter = OpenAdapter()
    /// Test aid: in a fake cloud, files under this folder count as iCloud Drive files.
    private var fakeCloudRoot: URL?
    private(set) lazy var cloud: CloudSongs = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PlayawayFakeCloud") {
            let fake = CloudSongs(scripted: ["Demo Two": .succeeds(after: 2), "Demo Three": .fails(after: 5)])
            fake.fakeRoot = fakeCloudRoot
            return fake
        }
        #endif
        return CloudSongs()
    }()
    private(set) lazy var downloads = DownloadOnPlayCoordinator(downloader: cloud, player: self)
    private var pendingPlays: [SongID: (session: PlaylistSession, track: Track)] = [:]
    /// Songs being fetched from iCloud only to be restored after a relaunch: when one arrives it is loaded paused at its
    /// remembered place, not played.
    private var pendingRestores: [SongID: Double] = [:]
    @Published private(set) var cloudRevision = 0
    private(set) lazy var openCoordinator = OpenCoordinator(classifier: FormatClassifier(), engine: engine,
                                                            notices: openAdapter, playlists: openAdapter)
    private let launchTimer: LaunchTimer?
    private let launchStore = LaunchReportStore()
    private var firstScreenReported = false
    private var refreshGeneration = 0
    private var lastPositionSave: Date?
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
            fakeCloudRoot = fake
        } else if let cached = UserDefaults.standard.string(forKey: Self.cloudFolderKey),
                  FileManager.default.fileExists(atPath: cached) {
            cloudLibrary = PlaylistLibrary(folder: URL(fileURLWithPath: cached), layout: .folderPerPlaylist)
        }
        let now = Date()
        if let start = LaunchFacts.processStart(), let boot = LaunchFacts.deviceBoot() {
            launchTimer = LaunchTimer(processStart: start, kind: launchKind(previousLaunch: launchStore.lastLaunch, deviceBoot: boot))
        } else { launchTimer = nil }
        launchStore.noteLaunch(at: now)
        // The playing position is drawn by the screen on its own clock, straight from the engine, so the transport does not
        // need to announce it four times a second.
        transport = TransportViewModel(engine: engine, registry: registry, runsTimer: false)
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
        filesPresenter.model = self
        if !fakeCloud { resolveICloud() }
        cloud.onEvent = { [weak self] event in
            guard let self else { return }
            self.downloads.handle(event)
            self.cloudRevision += 1
        }
        refresh()
        transport.startHandler = { [weak self] in
            guard let self else { return false }
            return self.downloads.transportPlay() == .ignored      // a song is still downloading: Play is taken and ignored
        }
        restoreMemory()
        #if DEBUG
        // Test aid: once the card opens, move to the next song after 10 s and again after 30 s, so a test can watch the sheet
        // resize without its own tap holding the screen still.
        if ProcessInfo.processInfo.arguments.contains("-PlayawayAutoNext") {
            $cardOpen.removeDuplicates().sink { [weak self] open in
                guard open else { return }
                for delay in [10.0, 30.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { try? self?.transport.next() }
                }
            }.store(in: &cancellables)
        }
        #endif
        $path.dropFirst().sink { [weak self] _ in self?.saveMemory(force: true) }.store(in: &cancellables)
        // The place is saved about every five seconds while a song plays (the throttle is in saveMemory).
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.saveMemory(force: false) }.store(in: &cancellables)
    }

    // MARK: Remembering what was playing

    /// Temporary, for build 17: what the launch-time restore found and where it stopped, shown on the playlists screen.
    @Published private(set) var restoreReport = "restore: not run yet"

    private func restoreMemory() {
        let saved = memoryStore.load()
        var report = "saved: \(saved.openPlaylists.count) open playlist(s), song \(saved.nowPlaying == nil ? "none" : "yes")"
        let existing = Set(entries.map { memoryKey($0.url) })
        report += " · listed now: \(existing.count) (cloud library \(cloudLibrary == nil ? "absent" : "present"))"
        let memory = saved.restoring(existingPlaylists: existing) { [self] name, id in
            let url = playlistURL(forFileName: name)
            if case .loaded(let playlist) = library(for: url).load(url) { return playlist.track(withID: id) != nil }
            return false
        }
        path = memory.openPlaylists.map { playlistURL(forFileName: $0) }
        report += " · kept after checking: \(memory.openPlaylists.count) playlist(s), song \(memory.nowPlaying == nil ? "none" : "yes")"
        defer { restoreReport = report }
        guard let point = memory.nowPlaying else { return }
        let url = playlistURL(forFileName: point.playlistFileName)
        // The remembered song is loaded into the engine paused at its place, so everything that shows it (the title, the
        // length, the place) is the engine's own, exactly as for any paused song. A song that is not on this device is not
        // waited for: it is not restored.
        guard let session = session(for: url) else { report += " · STOPPED: playlist file did not open"; return }
        guard let track = session.playlist.track(withID: point.trackID) else { report += " · STOPPED: song not in playlist"; return }
        guard case .resolved(let file) = TrackResolver().resolve(track.reference).0 else { report += " · STOPPED: song file not found from its bookmark"; return }
        session.model = self
        guard cloud.presence(of: file).isOnDevice else {
            // Evicted from the phone since: fetch it, and load it paused at its place when it arrives.
            let song = cloud.id(for: file)
            pendingPlays[song] = (session, track)
            pendingRestores[song] = point.positionSeconds
            downloads.request(song, source: .restore, isOnDevice: false)
            cloudRevision += 1
            report += " · song is in iCloud, not on this iPhone: fetching it, will load paused when it arrives"
            return
        }
        if session.player.load(track: track, atSeconds: point.positionSeconds) { becameActive(session); report += " · song loaded paused" }
        else { report += " · STOPPED: the audio engine refused the file (no access or unreadable)" }
    }

    /// Writes what the next launch needs. Position ticks are throttled; every other change passes `force`.
    func saveMemory(force: Bool) {
        if !force {
            guard engine.state == .playing, shouldSavePosition(lastSaved: lastPositionSave, now: Date()) else { return }
        }
        lastPositionSave = Date()
        var nowPlaying: ResumePoint?
        if engine.state != .idle, let session = activeSession, let track = session.player.current {
            nowPlaying = ResumePoint(playlistFileName: memoryKey(session.url), trackID: track.id,
                                     positionSeconds: engine.position)
        }
        memoryStore.save(ListeningMemory(openPlaylists: path.map { memoryKey($0) }, nowPlaying: nowPlaying))
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
        if keepExisting, FileManager.default.fileExists(atPath: folder.appendingPathComponent("Demo.\(playlistFileExtension)").path) || (cloudLibrary?.entries().contains { $0.name == "Demo" } ?? false) { return }
        if let leftovers = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for file in leftovers where file.pathExtension == playlistFileExtension { try? FileManager.default.removeItem(at: file) }
        }
        guard let playlistURL = try? library.create(named: "Demo") else { return }
        // A list longer than the screen, so tests can scroll to the last song.
        let repeats = ProcessInfo.processInfo.arguments.contains("-PlayawayLongList") ? 6 : 1
        var songs = Array(repeating: urls, count: repeats).flatMap { $0 }
        // Test aid: a song whose file is gone, as when an old playlist's songs were moved or deleted since it was made.
        let goneSong = folder.appendingPathComponent("Gone Song.wav")
        if ProcessInfo.processInfo.arguments.contains("-PlayawaySeedGoneSong") {
            try? tone(5, hz: 300).write(to: goneSong)
            songs.append(goneSong)
        }
        let result = adding(songs, to: Playlist(), classifier: FormatClassifier())
        _ = library.save(result.playlist, to: playlistURL)
        try? FileManager.default.removeItem(at: goneSong)
    }
    #endif

    /// Called by a playlist session whenever its player starts something, so the card knows the playlist.
    func becameActive(_ session: PlaylistSession) { activeSession = session }

    private func engineChanged() {
        let url = engine.currentURL
        saveMemory(force: engine.state != .playing || url != metadataURL)
        if url != metadataURL {
            metadataURL = url
            metadata = url.map { TrackMetadata.fallback(for: $0) }
            if let url { Task { [weak self] in
                var loaded = await loadTrackMetadata(for: url)
                #if DEBUG
                // Test aid: one song has artwork that arrives a moment after the song starts, as real artwork does.
                if ProcessInfo.processInfo.arguments.contains("-PlayawayFakeArtwork"), url.lastPathComponent.hasPrefix("Demo Two") {
                    try? await Task.sleep(for: .seconds(0.4))
                    loaded.artworkData = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).pngData { context in
                        UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
                    }
                }
                #endif
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
    var playerBarVisible: Bool { transport.state != .idle }
    @Published var failureMessage: String?
    private var queuedMessages: [String] = []

    /// Shows a message now, or after the one on screen has been dismissed, so none is lost.
    func enqueueMessage(_ message: String) {
        if failureMessage == nil { failureMessage = message } else { queuedMessages.append(message) }
    }

    func dismissFailureMessage() { failureMessage = queuedMessages.isEmpty ? nil : queuedMessages.removeFirst() }

    // MARK: Songs entering an iCloud playlist (the Files question)

    @Published var showFilesPrompt = false
    private var filesChoiceContinuation: CheckedContinuation<FilesChoice, Never>?
    private let filesPresenter = FilesPresenterAdapter()

    func presentFilesChoice() async -> FilesChoice {
        await withCheckedContinuation { continuation in
            filesChoiceContinuation = continuation
            showFilesPrompt = true
        }
    }

    func answerFilesPrompt(_ choice: FilesChoice) {
        showFilesPrompt = false
        filesChoiceContinuation?.resume(returning: choice)
        filesChoiceContinuation = nil
    }

    /// Runs the one shared flow for songs that have just entered a playlist, or that turning sync on brings in. Only
    /// a playlist in the Playaway folder is asked about; a playlist that is only on this phone is left alone.
    func songsEntered(_ tracks: [Track], in session: PlaylistSession, source: IntakeSource) {
        guard let cloudLibrary, library(for: session.url) === cloudLibrary else { return }
        let fakeRoot = cloud.fakeRoot
        let flow = SongIntakeFlow(root: cloudLibrary.folder, isUbiquitous: { CloudSongs.isUbiquitous($0, fakeRoot: fakeRoot) }, resolve: { track in
            guard case .resolved(let url) = TrackResolver().resolve(track.reference).0 else { return nil }
            _ = url.startAccessingSecurityScopedResource()
            return url
        }, fileSystem: SystemTransferFileSystem(), presenter: filesPresenter)
        let playlist = session.playlist
        let name = session.name
        Task { @MainActor [weak self] in
            let outcome = await Task.detached { await flow.run(playlist: playlist, playlistName: name, tracks: tracks, source: source) }.value
            guard let self, outcome.playlist != session.playlist else { return }
            session.apply(outcome.playlist)
            self.songURLs.removeAll()
            self.cloudRevision += 1
            self.pendingPlays.removeAll()
        }
    }

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

    private static let cloudMemoryPrefix = "iCloud/"

    /// How a playlist is remembered: its file name on the phone, or its path inside the shared iCloud folder. A name on
    /// its own would be ambiguous when the same name exists in both places.
    private func memoryKey(_ url: URL) -> String {
        if let cloudLibrary, url.path.hasPrefix(cloudLibrary.folder.path + "/") {
            return Self.cloudMemoryPrefix + String(url.path.dropFirst(cloudLibrary.folder.path.count + 1))
        }
        return url.lastPathComponent
    }

    /// A remembered playlist is found by that key.
    private func playlistURL(forFileName name: String) -> URL {
        if name.hasPrefix(Self.cloudMemoryPrefix), let cloudLibrary {
            return cloudLibrary.folder.appendingPathComponent(String(name.dropFirst(Self.cloudMemoryPrefix.count)))
        }
        return library.folder.appendingPathComponent(name)
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
            playExplainingFailure(track, in: session); return
        }
        let song = cloud.id(for: url)
        pendingPlays[song] = (session, track)
        downloads.request(song, source: .list, isOnDevice: cloud.presence(of: url).isOnDevice)
        cloudRevision += 1
    }

    func startPlayback(of song: SongID) {
        guard let pending = pendingPlays[song] else { return }
        if let place = pendingRestores.removeValue(forKey: song) {
            if pending.session.player.load(track: pending.track, atSeconds: place) { becameActive(pending.session) }
            cloudRevision += 1
            return
        }
        playExplainingFailure(pending.track, in: pending.session)
        cloudRevision += 1
    }

    /// Plays a song, and when it does not start says why, rather than leaving a tap that does nothing (an old playlist
    /// whose songs have moved or been deleted looked exactly like that: no sound, no controller, no word).
    private func playExplainingFailure(_ track: Track, in session: PlaylistSession) {
        becameActive(session)
        session.player.play(track: track)
        guard session.player.current?.id != track.id || engine.state == .idle else { return }
        let name = track.reference.fileName
        switch TrackResolver().resolve(track.reference).0 {
        case .resolved:
            failureMessage = "“\(name)” could not be played. The file may be damaged or in a format Playaway can't play."
        default:
            failureMessage = "“\(name)” can't be found. Its file may have been moved, renamed or deleted."
        }
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
        return SongRowCloudDisplay(presence: cloud.presence(of: url), tracked: tracked == .onThisDevice ? nil : tracked)
    }

    func cloudIconTapped(_ track: Track, session: PlaylistSession) {
        guard let display = cloudDisplay(for: track), let url = songURL(for: track) else { return }
        let song = cloud.id(for: url)
        pendingPlays[song] = (session, track)
        switch cloudIconTapAction(state: display.icon, kind: .song) {
        case .cancelDownload: downloads.cancel(song)
        case .retryDownload: downloads.retry(song)
        case .openSyncDialog:
            // A song outside the Playaway folder: ask about it as for any song entering an iCloud playlist, or offer to move the
            // playlist itself if it is still only on this phone.
            if let cloudLibrary, library(for: session.url) === cloudLibrary { songsEntered([track], in: session, source: .iPhoneAdd) }
            else if let entry = entries.first(where: { $0.url == session.url }) { beginSync(entry) }
        case .none, .cancelSync: break
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
                if let session = self.session(for: newURL) { self.songsEntered(session.playlist.tracks, in: session, source: .turnOnSync) }
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
        entries = allEntries()
        saveMemory(force: true)
        UIAccessibility.post(notification: .announcement, argument: "Playlist deleted")
    }

    /// A song or playlist opened from outside replaces the playlist that was playing.
    func endActiveSession() {
        activeSession?.player.end()
        activeSession = nil
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
