import Foundation
import Combine

/// The state the transport controls show, and every user action they offer. Windows and scripts call the same
/// methods, so a click and its script give the same result by construction.
package final class TransportViewModel: ObservableObject {
    package static let positionUpdateInterval: TimeInterval = 0.25

    @Published package private(set) var state: TransportState
    @Published package private(set) var position: Double = 0
    @Published package private(set) var duration: Double = 0
    @Published package private(set) var volume: Double
    @Published package private(set) var isMuted: Bool
    @Published package private(set) var nowPlaying: String = ""
    @Published package private(set) var hasPlaylistSession: Bool = false
    /// "Track 2 of 5" while a playlist session has a current track in the playlist; empty otherwise.
    @Published package private(set) var trackPosition: String = ""

    private let engine: PlaybackEngine
    private let registry: ActiveSessionRegistry
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?

    /// Starts something when Play is pressed with nothing loaded: the front playlist, else the last single file.
    package var startHandler: (() -> Bool)?
    /// Asks the playlist session that is active, if any.
    package var activePlayerProvider: () -> PlaylistPlayer? = { nil }

    /// The first state published already holds the restored volume and mute, never a default replaced later.
    package init(engine: PlaybackEngine, registry: ActiveSessionRegistry, runsTimer: Bool = true) {
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

    package var isPlaying: Bool { state == .playing }
    package var trackControlsAvailable: Bool { state != .idle }
    package var skipControlsAvailable: Bool { state != .idle && activePlayerProvider()?.isSessionActive == true }

    package func refresh() {
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

    package enum ActionError: Error, Equatable {
        case nothingPlaying
        case invalidSeekPosition
        case invalidVolume
    }

    /// Play: resumes when paused, starts the front playlist (or the last single file) when idle, otherwise nothing.
    package func play() throws {
        switch engine.state {
        case .paused: engine.resume()
        case .playing: break
        case .idle: if startHandler?() != true { throw ActionError.nothingPlaying }
        }
    }

    package func pause() throws {
        guard engine.state == .playing else {
            if engine.state == .paused { return }
            throw ActionError.nothingPlaying
        }
        engine.pause()
    }

    /// The Play/Pause control: Pause while playing, Play otherwise.
    package func playPause() {
        if engine.state == .playing { engine.pause() } else { try? play() }
    }

    package func stop() throws {
        guard engine.state != .idle else { throw ActionError.nothingPlaying }
        engine.stop()
    }

    package func seek(toSeconds seconds: Double) throws {
        guard engine.state != .idle else { throw ActionError.nothingPlaying }
        guard engine.seek(toSeconds: seconds) else { throw ActionError.invalidSeekPosition }
    }

    package func next() throws {
        guard engine.state != .idle else { throw ActionError.nothingPlaying }
        activePlayerProvider()?.next()
    }

    package func previous() throws {
        guard engine.state != .idle else { throw ActionError.nothingPlaying }
        activePlayerProvider()?.previous()
    }

    /// Volume is the player's own level, 0.0 to 1.0. Out-of-range values are clamped, a non-number is refused.
    package func setVolume(_ level: Double) throws {
        guard level.isFinite else { throw ActionError.invalidVolume }
        engine.volume = level
    }

    /// Script volume, a whole number from `scriptVolumeMin` to `scriptVolumeMax`, mapped to the engine range.
    package func setScriptVolume(_ value: Int) throws {
        guard value >= scriptVolumeMin, value <= scriptVolumeMax else { throw ActionError.invalidVolume }
        try setVolume(Double(value) / Double(scriptVolumeMax))
    }

    package func setMuted(_ muted: Bool) { engine.setMuted(muted) }
    package func toggleMute() { engine.setMuted(!engine.isMuted) }

    package static func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        let secondsPerMinute = 60
        return String(format: "%d:%02d", total / secondsPerMinute, total % secondsPerMinute)
    }
}
