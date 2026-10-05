import Foundation
import Combine

/// The state the transport controls show, and every user action they offer. Windows and scripts call the same
/// methods, so a click and its script give the same result by construction.
final class TransportViewModel: ObservableObject {
    static let positionUpdateInterval: TimeInterval = 0.25

    @Published private(set) var state: TransportState
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var volume: Double
    @Published private(set) var isMuted: Bool
    @Published private(set) var nowPlaying: String = ""
    @Published private(set) var hasPlaylistSession: Bool = false
    /// "Track 2 of 5" while a playlist session has a current track in the playlist; empty otherwise.
    @Published private(set) var trackPosition: String = ""

    private let engine: PlaybackEngine
    private let registry: ActiveSessionRegistry
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?

    /// Starts something when Play is pressed with nothing loaded: the front playlist, else the last single file.
    var startHandler: (() -> Bool)?
    /// Asks the playlist session that is active, if any.
    var activePlayerProvider: () -> PlaylistPlayer? = { nil }

    /// The first state published already holds the restored volume and mute, never a default replaced later.
    init(engine: PlaybackEngine, registry: ActiveSessionRegistry, runsTimer: Bool = true) {
        self.engine = engine
        self.registry = registry
        state = engine.state
        volume = engine.volume
        isMuted = engine.isMuted
        engine.events.sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        if runsTimer { startTimer() }
        refresh()
    }

    deinit { timer?.invalidate() }

    // MARK: State

    var isPlaying: Bool { state == .playing }
    var trackControlsAvailable: Bool { state != .idle }
    var skipControlsAvailable: Bool { state != .idle && activePlayerProvider()?.isSessionActive == true }

    func refresh() {
        state = engine.state
        position = engine.position
        duration = engine.duration
        volume = engine.volume
        isMuted = engine.isMuted
        nowPlaying = engine.currentURL?.lastPathComponent ?? ""
        hasPlaylistSession = activePlayerProvider()?.isSessionActive == true
        trackPosition = hasPlaylistSession
            ? activePlayerProvider()?.currentPosition.map { "Track \($0.place) of \($0.of)" } ?? "" : ""
    }

    private func startTimer() {
        let timer = Timer(timeInterval: Self.positionUpdateInterval, repeats: true) { [weak self] _ in
            guard let self, self.engine.state == .playing else { return }
            self.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)      // keeps ticking while a menu is open or a window is resized
        self.timer = timer
    }

    // MARK: Actions

    enum ActionError: Error, Equatable {
        case nothingPlaying
        case invalidSeekPosition
        case invalidVolume
    }

    /// Play: resumes when paused, starts the front playlist (or the last single file) when idle, otherwise nothing.
    func play() throws {
        switch engine.state {
        case .paused: engine.resume()
        case .playing: break
        case .idle: if startHandler?() != true { throw ActionError.nothingPlaying }
        }
    }

    func pause() throws {
        guard engine.state == .playing else {
            if engine.state == .paused { return }
            throw ActionError.nothingPlaying
        }
        engine.pause()
    }

    /// The Play/Pause control: Pause while playing, Play otherwise.
    func playPause() {
        if engine.state == .playing { engine.pause() } else { try? play() }
    }

    func stop() throws {
        guard engine.state != .idle else { throw ActionError.nothingPlaying }
        engine.stop()
    }

    func seek(toSeconds seconds: Double) throws {
        guard engine.state != .idle else { throw ActionError.nothingPlaying }
        guard engine.seek(toSeconds: seconds) else { throw ActionError.invalidSeekPosition }
    }

    func next() throws {
        guard engine.state != .idle else { throw ActionError.nothingPlaying }
        activePlayerProvider()?.next()
    }

    func previous() throws {
        guard engine.state != .idle else { throw ActionError.nothingPlaying }
        activePlayerProvider()?.previous()
    }

    /// Volume is the player's own level, 0.0 to 1.0. Out-of-range values are clamped, a non-number is refused.
    func setVolume(_ level: Double) throws {
        guard level.isFinite else { throw ActionError.invalidVolume }
        engine.volume = level
    }

    /// Script volume, a whole number from `scriptVolumeMin` to `scriptVolumeMax`, mapped to the engine range.
    func setScriptVolume(_ value: Int) throws {
        guard value >= scriptVolumeMin, value <= scriptVolumeMax else { throw ActionError.invalidVolume }
        try setVolume(Double(value) / Double(scriptVolumeMax))
    }

    func setMuted(_ muted: Bool) { engine.setMuted(muted) }
    func toggleMute() { engine.setMuted(!engine.isMuted) }

    static func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        let secondsPerMinute = 60
        return String(format: "%d:%02d", total / secondsPerMinute, total % secondsPerMinute)
    }
}
