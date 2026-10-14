import SwiftUI
import Combine
import AVFoundation
import MediaPlayer
import PlayawayCore

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

    func play(_ track: Track) { model?.becameActive(self); player.play(track: track) }
    func start() { model?.becameActive(self); player.start() }
    weak var model: AppModel?

    private func replace(_ updated: Playlist) {
        playlist = updated
        if case .writeFailed = library.save(updated, to: url) { notice = "The playlist could not be saved." }
    }
}

@MainActor
final class AppModel: ObservableObject {
    let library: PlaylistLibrary
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
        refresh()
        transport.startHandler = { [weak self] in self?.resumeFromMemory() ?? false }
        restoreMemory()
        $path.dropFirst().sink { [weak self] _ in self?.saveMemory(force: true) }.store(in: &cancellables)
        transport.$position.sink { [weak self] _ in self?.saveMemory(force: false) }.store(in: &cancellables)
    }

    // MARK: Remembering what was playing

    private func restoreMemory() {
        let existing = Set(entries.map { $0.url.lastPathComponent })
        let memory = memoryStore.load().restoring(existingPlaylists: existing) { [library] name, id in
            if case .loaded(let playlist) = library.load(library.folder.appendingPathComponent(name)) {
                return playlist.track(withID: id) != nil
            }
            return false
        }
        path = memory.openPlaylists.map { library.folder.appendingPathComponent($0) }
        guard let point = memory.nowPlaying else { return }
        let url = library.folder.appendingPathComponent(point.playlistFileName)
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
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("Demo.\(playlistFileExtension)"))
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

    func refresh() { entries = library.entries() }

    func createPlaylist(named name: String) throws -> URL {
        let url = try library.create(named: name)
        refresh()
        return url
    }

    func session(for url: URL) -> PlaylistSession? {
        if let existing = sessions[url] { return existing }
        guard case .loaded(let playlist) = library.load(url) else { return nil }
        let session = PlaylistSession(url: url, playlist: playlist, library: library, model: self)
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
