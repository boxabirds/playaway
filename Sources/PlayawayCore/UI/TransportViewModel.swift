import Foundation
import Combine

/// The state the transport controls show, and every user action they offer. Windows and scripts call the same
/// methods, so a click and its script give the same result by construction.
package final class TransportViewModel: ObservableObject {
    package static let positionUpdateInterval: TimeInterval = 0.25

    // Everything below is read from the engine at the moment it is asked for. There is no stored copy of any of it, so
    // what a screen shows can never differ from what the engine is actually doing. The engine is the one place where
    // playback state lives; this class is a view of it plus the actions on it.
    package var state: TransportState { engine.state }
    package var position: Double { engine.position }
    package var duration: Double { engine.duration }
    package var volume: Double { engine.volume }
    package var isMuted: Bool { engine.isMuted }
    package var nowPlaying: String { engine.currentURL?.lastPathComponent ?? "" }
    package var hasPlaylistSession: Bool { activePlayerProvider()?.isSessionActive == true }
    /// "Track 2 of 5" while a playlist session has a current track in the playlist; empty otherwise.
    package var trackPosition: String {
        hasPlaylistSession ? activePlayerProvider()?.currentPosition.map { "Track \($0.place) of \($0.of)" } ?? "" : ""
    }

    private let engine: PlaybackEngine
    private let registry: ActiveSessionRegistry
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?

    /// Starts something when Play is pressed with nothing loaded: the front playlist, else the last single file.
    package var startHandler: (() -> Bool)?
    /// Asks the playlist session that is active, if any.
    package var activePlayerProvider: () -> PlaylistPlayer? = { nil }

    /// `runsTimer` makes observers hear about the playing position four times a second. A screen that draws the position
    /// itself on a clock does not need it.
    package init(engine: PlaybackEngine, registry: ActiveSessionRegistry, runsTimer: Bool = true) {
        self.engine = engine
        self.registry = registry
        engine.events.sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        if runsTimer { startTimer() }
    }

    deinit { timer?.invalidate() }

    // MARK: State

    package var isPlaying: Bool { state == .playing }
    package var trackControlsAvailable: Bool { state != .idle }
    package var skipControlsAvailable: Bool { state != .idle && activePlayerProvider()?.isSessionActive == true }

    /// Tells observers that something they show may have changed. The values themselves are read live from the engine.
    package func refresh() { objectWillChange.send() }

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
        if isScrubbing { armScrubWatchdog() }
        refresh()
    }

    // MARK: Scrubbing

    private var scrubWasPlaying = false
    private var isScrubbing = false
    private var scrubWatchdog: Timer?
    /// If a scrub shows no sign of life for this long (no move and no lift reported, for example because another gesture
    /// took the touch away) playback carries on, so a scrub can never leave the song paused for good.
    package var scrubTimeout: TimeInterval = 2

    /// The person put a finger on the position slider. Playback pauses for the drag, as in the system apps, so nothing
    /// is heard from the places the slider passes through and nothing is replayed.
    package func beginScrub() {
        guard engine.state != .idle, !isScrubbing else { return }
        isScrubbing = true
        scrubWasPlaying = engine.state == .playing
        if scrubWasPlaying { engine.pause() }
        armScrubWatchdog()
    }

    private func armScrubWatchdog() {
        scrubWatchdog?.invalidate()
        let watchdog = Timer(timeInterval: scrubTimeout, repeats: false) { [weak self] _ in
            guard let self, self.isScrubbing else { return }
            try? self.endScrub(toSeconds: self.engine.position)
        }
        RunLoop.main.add(watchdog, forMode: .common)
        scrubWatchdog = watchdog
    }

    /// The finger lifted at `seconds`: one seek to that place, then playback carries on if it was playing before.
    package func endScrub(toSeconds seconds: Double) throws {
        defer { isScrubbing = false; scrubWasPlaying = false; scrubWatchdog?.invalidate(); scrubWatchdog = nil }
        guard engine.state != .idle else { throw ActionError.nothingPlaying }
        guard engine.seek(toSeconds: seconds) else {
            if scrubWasPlaying { engine.resume() }       // an impossible place leaves the song playing from where it was
            throw ActionError.invalidSeekPosition
        }
        if scrubWasPlaying { engine.resume() }
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
