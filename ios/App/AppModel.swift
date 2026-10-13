import SwiftUI
import Combine
import AVFoundation
import PlayawayCore

/// One open playlist: its songs, its player, and saving after every change.
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
    private var sessions: [URL: PlaylistSession] = [:]
    private var cancellables = Set<AnyCancellable>()

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        library = PlaylistLibrary(folder: documents)
        transport = TransportViewModel(engine: engine, registry: registry)
        configureAudioSession()
        refresh()
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
