import SwiftUI
import Combine
import AVFoundation
import MediaPlayer
import PlayawayCore

/// One open playlist: its songs, its player, and saving after every change.
@MainActor
final class PlaylistSession: ObservableObject {
    let url: URL
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
        if ProcessInfo.processInfo.arguments.contains("-PlayawaySeedDemo") { seedDemoPlaylist(in: documents) }
        #endif
        refresh()
    }

    #if DEBUG
    /// Test aid: a playlist of two short generated tones, so UI tests can play real files.
    private func seedDemoPlaylist(in folder: URL) {
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
        // Start every seeded launch from the same playlist, whatever earlier tests changed.
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("Demo.\(playlistFileExtension)"))
        guard let playlistURL = try? library.create(named: "Demo") else { return }
        let result = adding(urls, to: Playlist(), classifier: FormatClassifier())
        _ = library.save(result.playlist, to: playlistURL)
    }
    #endif

    /// Called by a playlist session whenever its player starts something, so the card knows the playlist.
    func becameActive(_ session: PlaylistSession) { activeSession = session }

    private func engineChanged() {
        let url = engine.currentURL
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

    func openPlaylist(_ url: URL) { path.append(url) }

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
