import SwiftUI
import CryptoKit
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

    /// The file-following state (story 39): reloads and rebases are decided in the shared core.
    private var followed: FollowedPlaylist
    private var presenter: SessionPresenter?

    /// `followsFile` is true for a playlist in the iCloud folder, where another device may change its file.
    init(url: URL, playlist: Playlist, library: PlaylistLibrary, model: AppModel, followsFile: Bool = false) {
        self.url = url
        self.playlist = playlist
        self.library = library
        followed = Self.makeFollowed(url: url, playlist: playlist, library: library)
        var provider: () -> Playlist = { playlist }
        let box = Box()
        provider = { box.session?.playlist ?? playlist }
        player = PlaylistPlayer(playlist: provider, playlistFolder: { box.session?.folder }, settings: model.settings,
                                resolver: model.resolver, engine: model.engine, marks: model.marks, registry: model.registry)
        box.session = self
        player.changes.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        if followsFile { followFile() }
    }
    private final class Box { weak var session: PlaylistSession? }

    private static func makeFollowed(url: URL, playlist: Playlist, library: PlaylistLibrary) -> FollowedPlaylist {
        FollowedPlaylist(url: url, playlist: playlist, fingerprint: PlaylistStore().fingerprint(of: url), files: LibraryFiles(library: library),
                         isInContainer: { CloudFolder.relativePath(inContainer: $0.lastKnownPath) != nil })
    }

    /// The library's own load and save, with the store's fingerprint, so following the file changes no write path.
    private struct LibraryFiles: PlaylistFileReading {
        let library: PlaylistLibrary
        func fingerprint(of url: URL) -> FileFingerprint? { PlaylistStore().fingerprint(of: url) }
        func load(from url: URL) -> LoadResult { library.load(url) }
        func save(_ playlist: Playlist, to url: URL) -> SaveResult { library.save(playlist, to: url) }
    }

    /// Registers this session as the file's presenter, so the system says when something else wrote it.
    private func followFile() {
        guard presenter == nil else { return }
        let presenter = SessionPresenter(url: url) { [weak self] in self?.fileChangedUnderUs() }
        NSFileCoordinator.addFilePresenter(presenter)
        self.presenter = presenter
    }

    /// Called when the session is dropped or its file moves; a presenter left registered would outlive the session.
    func stopFollowing() {
        if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
        presenter = nil
    }

    /// Whether another device's change to the file is being watched for (iCloud playlists only).
    var isFollowingFile: Bool { presenter != nil }

    private func fileChangedUnderUs() {
        followed.edited(playlist)
        switch followed.fileChanged() {
        case .replaced, .merged:
            playlist = followed.playlist
            if followed.isEdited, case .writeFailed = followed.save() { notice = "The playlist could not be saved." }
            model?.playlistChangedUnderUs(self)
        case .unchanged, .gone, .unreadable:
            break
        }
    }

    var name: String { url.deletingPathExtension().lastPathComponent }
    /// Where the playlist's file is; a song another device stored is looked for here by name.
    var folder: URL { url.deletingLastPathComponent() }

    /// The playlist now lives at a new place, for example after its unsaved songs were saved to a file.
    func rebase(to newURL: URL) {
        _ = newURL.startAccessingSecurityScopedResource()
        url = newURL
        followed = followed.movedTo(newURL)
        let wasFollowing = presenter != nil
        stopFollowing()
        if wasFollowing { followFile() }
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
        followed.edited(updated)
        let result = followed.save()                       // a newer file (the other device's) is taken in first
        if followed.playlist != updated { playlist = followed.playlist }
        if case .writeFailed = result { notice = "The playlist could not be saved." }
    }
}

/// The system's way of telling a session that something else wrote its file. Callbacks arrive on the main queue.
final class SessionPresenter: NSObject, NSFilePresenter, @unchecked Sendable {   // calls back on the main queue only
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue.main
    private let onChange: () -> Void
    init(url: URL, onChange: @escaping () -> Void) { presentedItemURL = url; self.onChange = onChange }
    func presentedItemDidChange() { MainActor.assumeIsolated { onChange() } }
}

/// Lets the shared open path (the same one the Mac uses) hand playlists to the app and show its notices. Calls come
/// from the system's open-URL event on the main thread.
final class OpenAdapter: PlaylistOpening, NoticePresenting, @unchecked Sendable {   // touches the model only on the main actor
    weak var model: AppModel?
    func canOpen(_ url: URL) -> Bool { url.pathExtension == playlistFileExtension }
    func open(_ url: URL) { MainActor.assumeIsolated { model?.openExternal(url) } }
    func endActivePlayback() { MainActor.assumeIsolated { model?.endActiveSession() } }
    func show(_ notice: Notice) { MainActor.assumeIsolated { model?.failureMessage = notice.title } }
}

/// The resolver every session shares. Its iCloud folder is filled in once the system says where the Playaway folder
/// is, so a song another device stored can be found at the same place here.
final class LiveResolver: TrackResolving {
    var current = TrackResolver(cloudDocuments: nil)
    func resolve(_ ref: TrackReference) -> (TrackStatus, TrackReference) { current.resolve(ref) }
    func resolve(_ ref: TrackReference, besidePlaylistAt folder: URL?) -> (TrackStatus, TrackReference) {
        current.resolve(ref, besidePlaylistAt: folder)
    }
    func accessNeeded(for ref: TrackReference, besidePlaylistAt folder: URL?) -> String? {
        current.accessNeeded(for: ref, besidePlaylistAt: folder)
    }
}

/// Lets the shared Files flow ask its question and show its messages through the app's screens.
final class FilesPresenterAdapter: FilesPromptPresenting, @unchecked Sendable {   // touches the model only on the main actor
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
    nonisolated private static let cloudContainer = CloudFolder.containerIdentifier
    /// Finds a song's file for every session; learns where the iCloud Playaway folder is once the system says.
    let resolver = LiveResolver()
    /// Where a song's portable location is on this device (story 40): the Playaway folder, and the iCloud Drive folders
    /// the person has allowed this device to read.
    let roots: GrantedCloudRoots
    private static let grantsFileName = "FolderGrants.json"
    /// Test aid: a folder standing in for the iCloud Drive root, so the grant flow runs without an account.
    var fakeDriveRoot: URL?
    private static let matchesFileName = "DeviceMatches.json"
    /// The restore sheet (story 41): its playlist, and whether it shows the explanation or the system's folder chooser.
    enum RestorePhase { case explain, pick }
    @Published var restoreSession: PlaylistSession?
    @Published var restorePhase: RestorePhase = .explain
    /// The playlist whose folder the system chooser is open for. The chooser closes its sheet when Open is tapped and only
    /// then reports the folder, so the answer must not depend on the sheet still being up (the bug: Open did nothing).
    var pickingSession: PlaylistSession?
    /// A restore that is searching a folder: shown as a progress card with a Cancel, so a big iCloud folder never looks frozen.
    struct RestoreProgress: Equatable { var folder: String; var looked: Int }
    @Published var restoreProgress: RestoreProgress?
    var restoreCancellation: CancelFlag?
    /// Read from the search, which runs off the main thread; set from the Cancel button.
    final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }
    /// Choosing a file for one song (Locate), and the offer of a whole folder after a song was added.
    @Published var locateShown = false
    var locateTarget: (session: PlaylistSession, track: Track)?
    @Published var nudgeFolderName: String?
    @Published var nudgePickerShown = false
    static let declinedNudgesKey = "declinedFolderNudges"
    /// What this playlist needs, worked out once per change of what is on disk and kept until something changes.
    struct AccessSnapshot { var plan: RecoveryPlan?; var unfound: [UnfoundSong]; var locked: Set<UUID> }
    var accessCache: [URL: (revision: Int, snapshot: AccessSnapshot)] = [:]
    let settings = PlayModeSettings()
    let engine = AVPlaybackEngine()
    let registry = ActiveSessionRegistry()
    let marks = ReadabilityMarkStore()
    let transport: TransportViewModel
    @Published private(set) var entries: [PlaylistEntry] = []
    @Published var cardOpen = false
    @Published var path: [URL] = []
    /// The playlist chosen in the iPad's sidebar (regular width); in the stack it mirrors the end of `path`.
    @Published var selectedPlaylist: URL?
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
    var pendingPlays: [SongID: (session: PlaylistSession, track: Track)] = [:]
    /// Where each song of the open playlists was last found on this device (see `songURL(for:in:)`).
    let songCache = ResolutionCache()
    /// Songs being fetched from iCloud only to be restored after a relaunch: when one arrives it is loaded paused at its
    /// remembered place, not played.
    var pendingRestores: [SongID: Double] = [:]
    @Published var cloudRevision = 0
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
    /// The lyrics experiment: its sheet for the song under way, and its switches.
    let lyrics = LyricsCoordinator()
    @Published var experimentsShown = false
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
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let grantStore = FolderGrantFileStore(url: support.appendingPathComponent(Self.grantsFileName))
        let matchStore = DeviceMatchFileStore(url: support.appendingPathComponent(Self.matchesFileName))
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PlayawayFakeDrive") {
            let drive = documents.appendingPathComponent("FakeDrive", isDirectory: true)
            if ProcessInfo.processInfo.arguments.contains("-PlayawaySeedDrivePlaylist"),
               !ProcessInfo.processInfo.arguments.contains("-PlayawayKeepMemory") {
                try? FileManager.default.removeItem(at: drive)
                try? FileManager.default.removeItem(at: support.appendingPathComponent(Self.grantsFileName))
                try? FileManager.default.removeItem(at: support.appendingPathComponent(Self.matchesFileName))
                UserDefaults.standard.removeObject(forKey: Self.declinedNudgesKey)
            }
            try? FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
            fakeDriveRoot = drive
            let prefix = drive.canonicalPath + "/"
            roots = GrantedCloudRoots(playawayDocuments: nil, store: grantStore, matchStore: matchStore, drivePath: { url in
                let path = url.canonicalPath
                return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
            })
        } else {
            roots = GrantedCloudRoots(playawayDocuments: nil, store: grantStore, matchStore: matchStore)
        }
        #else
        roots = GrantedCloudRoots(playawayDocuments: nil, store: grantStore, matchStore: matchStore)
        #endif
        resolver.current = TrackResolver(roots: roots)
        if fakeCloud {
            let fake = documents.appendingPathComponent("FakeICloud")
            if ProcessInfo.processInfo.arguments.contains("-PlayawaySeedDemo"),
               !ProcessInfo.processInfo.arguments.contains("-PlayawayKeepMemory") { try? FileManager.default.removeItem(at: fake) }
            try? FileManager.default.createDirectory(at: fake, withIntermediateDirectories: true)
            cloudLibrary = PlaylistLibrary(folder: fake, layout: .folderPerPlaylist)
            fakeCloudRoot = fake
            roots.playawayDocuments = fake
        } else if let cached = UserDefaults.standard.string(forKey: Self.cloudFolderKey),
                  FileManager.default.fileExists(atPath: cached) {
            cloudLibrary = PlaylistLibrary(folder: URL(fileURLWithPath: cached), layout: .folderPerPlaylist)
            roots.playawayDocuments = URL(fileURLWithPath: cached)
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
        lyrics.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        engine.events.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.engineChanged() }.store(in: &cancellables)
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-PlayawaySeedDemo") {
            if !arguments.contains("-PlayawayKeepMemory") { memoryStore.save(.empty); lyrics.resetForTests() }
            seedDemoPlaylist(in: documents, keepExisting: arguments.contains("-PlayawayKeepMemory"))
        }
        // Test aid: a playlist another device (a Mac) wrote into the Playaway folder, its references the Mac's.
        if arguments.contains("-PlayawaySeedForeignPlaylist"), let fake = fakeCloudRoot { seedForeignPlaylist(in: fake) }
        // Test aid: a playlist the iPhone wrote whose songs live in iCloud Drive/Mixdowns, in build-22 form (no cloud path).
        // Test aid (story 42): a playlist whose songs were added on a Mac from a folder that is not in iCloud.
        if arguments.contains("-PlayawaySeedElsewherePlaylist"), let fake = fakeCloudRoot { seedElsewherePlaylist(in: fake) }
        if arguments.contains("-PlayawaySeedDrivePlaylist"), let fake = fakeCloudRoot, let drive = fakeDriveRoot {
            seedDrivePlaylist(in: fake, drive: drive)
            seedMixedDrivePlaylist(in: fake, drive: drive)
        }
        // Test aid: after the given seconds, "another device" rewrites the open playlist's file with one more song.
        if let at = arguments.firstIndex(of: "-PlayawayRewriteOpenPlaylist"), at + 1 < arguments.count, let seconds = Double(arguments[at + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.rewriteOpenPlaylistAsAnotherDevice() }
        }
        // Test aid: the lyrics experiment on, with a ready-made sheet for "Demo One", so the panel needs no model.
        if arguments.contains("-PlayawayFakeLyrics"),
           let demoOne = (try? FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil))?
            .first(where: { $0.lastPathComponent.hasPrefix("Demo One") }) {
            lyrics.seedFakeSheet(for: demoOne)
        }
        #endif
        #if DEBUG
        // Test aid: what a playlist whose songs are downloading looks like to the list: the cloud state changes all the
        // time (a download reports progress twice a second), and the list must not be rebuilt under a finger.
        if ProcessInfo.processInfo.arguments.contains("-PlayawayChurnCloud") {
            Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.cloudRevision += 1 } }
        }
        #endif
        openAdapter.model = self
        filesPresenter.model = self
        if !fakeCloud { resolveICloud() }
        cloud.onEvent = { [weak self] event in
            guard let self else { return }
            if self.downloads.handle(event) { self.cloudRevision += 1 }      // not for a tick that changed nothing
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
        $path.sink { [weak self] trail in if let last = trail.last { self?.selectedPlaylist = last } }.store(in: &cancellables)
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
        guard case .resolved(let file) = resolver.resolve(track.reference, besidePlaylistAt: session.folder).0 else { report += " · STOPPED: song file not found from its bookmark"; return }
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


    /// Called by a playlist session whenever its player starts something, so the card knows the playlist.
    func becameActive(_ session: PlaylistSession) { activeSession = session }

    private func engineChanged() {
        let url = engine.currentURL
        saveMemory(force: engine.state != .playing || url != metadataURL)
        if url != metadataURL {
            metadataURL = url
            metadata = url.map { TrackMetadata.fallback(for: $0) }
            lyrics.songChanged(url)
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
        selectedPlaylist = url
    }

    /// Songs dropped on a playlist in the sidebar (story 38): added as Add Songs would; a playlist whose file cannot be
    /// read takes nothing and says so.
    @discardableResult
    func add(_ urls: [URL], toPlaylistAt playlist: URL) -> Bool {
        guard let session = session(for: playlist) else {
            failureMessage = "The playlist could not be read, so nothing was added to it."
            return false
        }
        let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
        session.add(urls)
        scoped.forEach { $0.stopAccessingSecurityScopedResource() }
        return true
    }

    /// Choosing a playlist, the one entry point for both forms (story 38): in the stack it is the path; in columns it
    /// is the sidebar's selection, the path stays empty and the card is closed. Playback is untouched by a choice.
    func select(_ url: URL?, in plan: ColumnPlan) {
        let outcome = IPadLayout.selection(choosing: url, plan: plan, cardOpen: cardOpen)
        selectedPlaylist = outcome.selected
        if plan == .stack {
            if let url { openPlaylist(url) } else { path = [] }
        } else {
            path = outcome.path
            cardOpen = outcome.cardOpen
        }
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
        let resolver = self.resolver, folder = session.folder
        let flow = SongIntakeFlow(root: cloudLibrary.folder, isUbiquitous: { CloudSongs.isUbiquitous($0, fakeRoot: fakeRoot) }, resolve: { track in
            guard case .resolved(let url) = resolver.resolve(track.reference, besidePlaylistAt: folder).0 else { return nil }
            _ = url.startAccessingSecurityScopedResource()
            return url
        }, fileSystem: SystemTransferFileSystem(), presenter: filesPresenter)
        let playlist = session.playlist
        let name = session.name
        Task { @MainActor [weak self] in
            let outcome = await Task.detached { await flow.run(playlist: playlist, playlistName: name, tracks: tracks, source: source) }.value
            guard let self, outcome.playlist != session.playlist else { return }
            session.apply(outcome.playlist)
            self.songCache.removeAll()
            self.cloudRevision += 1
            self.pendingPlays.removeAll()
        }
    }

    /// Another device changed an open playlist's file (story 39): everything drawn from it is read again.
    func playlistChangedUnderUs(_ session: PlaylistSession) {
        songCache.removeAll()
        cloudRevision += 1
        objectWillChange.send()
        refresh()
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
        roots.playawayDocuments = documents
        songCache.removeAll()                                 // a song another device stored may be findable now
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
        songCache.removeAll()
        if let session = sessions.removeValue(forKey: old) { session.rebase(to: new); sessions[new] = session }
        path = path.map { $0 == old ? new : $0 }
        if selectedPlaylist == old { selectedPlaylist = new }
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
        sessions[entry.url]?.stopFollowing()
        sessions[entry.url] = nil
        path.removeAll { $0 == entry.url }
        if selectedPlaylist == entry.url { selectedPlaylist = nil }
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
        let session = PlaylistSession(url: url, playlist: playlist, library: owner, model: self,
                                      followsFile: cloudLibrary != nil && owner === cloudLibrary)
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

