import Foundation
import Combine

/// The state the transport controls show, and every user action they offer. Windows and scripts call the same
/// methods, so a click and its script give the same result by construction.
@MainActor
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
    /// Invalidated in `deinit`, which is not on the main actor; the timer is only ever touched on the main thread before that.
    private nonisolated(unsafe) var timer: Timer?

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

    /// A timer whose body runs on the main actor. Timers fire on the run loop they were added to, which is the main one.
    private static func mainTimer(interval: TimeInterval, repeats: Bool, _ body: @escaping @MainActor () -> Void) -> Timer {
        Timer(timeInterval: interval, repeats: repeats) { _ in MainActor.assumeIsolated { body() } }
    }

    private func startTimer() {
        let timer = Self.mainTimer(interval: Self.positionUpdateInterval, repeats: true) { [weak self] in
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
        if isScrubbing { engine.stopPreviewLoop() }                         // moving again quiets the snippet
        if isScrubbing, engine.state == .playing { engine.pause() }       // and the song, if it was playing itself
        guard engine.seek(toSeconds: seconds) else { throw ActionError.invalidSeekPosition }
        if isScrubbing {
            scrubTarget = seconds
            scrubTrace.moved(at: clock()); armScrubWatchdog(); armHoldTimer(); if scrubWasPlaying { armPrepareTimer(after: scrubPrepareDelay) }
        }
        refresh()
    }

    // MARK: Scrubbing

    private var scrubWasPlaying = false
    private var isScrubbing = false
    private var scrubWatchdog: Timer?
    private var playheadWatch: Timer?
    private var holdTimer: Timer?
    private var prepareTimer: Timer?
    /// How long after the finger last moved the loop for that place starts being got ready, so that it is ready when the hold ends.
    package var scrubPrepareDelay: TimeInterval = 0.06
    /// How long the sound fades in when it takes over from the looping snippet at the lift.
    package static let handoffFade: TimeInterval = 0.02
    /// Where the finger is while a drag is in progress. The slider and its labels show this, not the engine, so the thumb
    /// never moves under the finger; outside a drag it is nil and everything shows the engine's own position.
    package private(set) var scrubTarget: Double?
    package var displayPosition: Double { scrubTarget ?? engine.position }
    /// How long the snippet that plays while the finger holds still is before it loops back to its start.
    package var scrubLoopLength: TimeInterval = TransportViewModel.defaultScrubLoopLength
    package static let defaultScrubLoopLength: TimeInterval = 1.0
    /// A lost finger-lift is only guessed at after this long while the snippet is playing (the song is already audible).
    package var previewWatchdogTimeout: TimeInterval = 10
    /// How long the finger must hold still on the slider before the song plays from that place, so it can be heard.
    package var scrubHoldDelay: TimeInterval = TransportViewModel.defaultScrubHoldDelay
    package static let defaultScrubHoldDelay: TimeInterval = 0.3
    /// What the last drag did, for the debug line on the card.
    package private(set) var scrubTrace = ScrubTrace()
    package var clock: () -> Date = Date.init
    /// If a scrub shows no sign of life for this long (no move and no lift reported, for example because another gesture
    /// took the touch away) playback carries on, so a scrub can never leave the song paused for good.
    package var scrubTimeout: TimeInterval = 2

    /// The person put a finger on the position slider. Playback pauses for the drag, as in the system apps, so nothing
    /// is heard from the places the slider passes through and nothing is replayed.
    package func beginScrub() {
        guard engine.state != .idle, !isScrubbing else { return }
        isScrubbing = true
        scrubWasPlaying = engine.state == .playing
        scrubTarget = engine.position
        scrubTrace.fingerDown(at: clock(), wasPlaying: scrubWasPlaying)
        if scrubWasPlaying { engine.pause(); armPrepareTimer(after: 0) }      // the engine starts warming at once
        armScrubWatchdog()
        refresh()
    }

    /// The finger holds still: the song plays from where the slider is, if it was playing before the drag.
    private func armHoldTimer() {
        holdTimer?.invalidate()
        guard scrubWasPlaying else { return }
        let timer = Self.mainTimer(interval: scrubHoldDelay, repeats: false) { [weak self] in
            guard let self, self.isScrubbing, self.engine.state == .paused else { return }
            let place = self.scrubTarget ?? self.engine.position
            if self.engine.startPreviewLoop(at: place, length: self.scrubLoopLength) {
                self.armScrubWatchdog(after: self.previewWatchdogTimeout)      // the snippet is audible; the song stays paused
            } else {
                self.engine.resume()                                          // no snippet possible: the song itself plays
            }
            self.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    /// Reads the snippet at the slider's place in the background once the finger has paused for a moment.
    private func armPrepareTimer(after delay: TimeInterval) {
        prepareTimer?.invalidate()
        let timer = Self.mainTimer(interval: delay, repeats: false) { [weak self] in
            guard let self, self.isScrubbing else { return }
            self.engine.prepareLoop(at: self.scrubTarget ?? self.engine.position, length: self.scrubLoopLength)
        }
        RunLoop.main.add(timer, forMode: .common)
        prepareTimer = timer
    }

    private func armScrubWatchdog(after interval: TimeInterval? = nil) {
        scrubWatchdog?.invalidate()
        let watchdog = Self.mainTimer(interval: interval ?? scrubTimeout, repeats: false) { [weak self] in
            guard let self, self.isScrubbing else { return }
            try? self.finishScrub(toSeconds: self.engine.position, how: .safetyTimer)
        }
        RunLoop.main.add(watchdog, forMode: .common)
        scrubWatchdog = watchdog
    }

    /// The finger lifted at `seconds`: one seek to that place, then playback carries on if it was playing before.
    package func endScrub(toSeconds seconds: Double) throws { try finishScrub(toSeconds: seconds, how: .lift) }

    private func finishScrub(toSeconds seconds: Double, how: ScrubTrace.End) throws {
        defer {
            isScrubbing = false; scrubWasPlaying = false; scrubWatchdog?.invalidate(); scrubWatchdog = nil
            holdTimer?.invalidate(); holdTimer = nil; prepareTimer?.invalidate(); prepareTimer = nil
            engine.stopPreviewLoop(); engine.endPreviewSession(); scrubTarget = nil
            watchPlayheadAfterResume()
            refresh()
        }
        scrubTrace.end(how, at: clock())
        guard engine.state != .idle else { throw ActionError.nothingPlaying }
        if engine.isPreviewing {                     // the snippet is looping: the song takes over from where the loop is
            if let place = engine.stopPreviewLoop() { _ = engine.seek(toSeconds: min(place, engine.duration)) }
            engine.resume(fadingIn: Self.handoffFade)
            scrubTrace.resumeRequested(at: clock())
            return
        }
        if engine.state == .playing { return }      // the song itself was playing (no snippet): carry on, never jump back
        guard engine.seek(toSeconds: seconds) else {
            if scrubWasPlaying { engine.resume(); scrubTrace.resumeRequested(at: clock()) }   // an impossible place leaves the song playing
            throw ActionError.invalidSeekPosition
        }
        if scrubWasPlaying { engine.resume(); scrubTrace.resumeRequested(at: clock()) }
    }

    /// Notes when the playhead is first seen moving after a resume, polled finely so the trace can tell a late lift from a
    /// slow restart of the sound.
    private func watchPlayheadAfterResume() {
        playheadWatch?.invalidate()
        guard scrubTrace.awaitingPlayhead else { return }
        let placeAtResume = engine.position
        let deadline = clock().addingTimeInterval(Self.playheadWatchLimit)
        let watch = Self.mainTimer(interval: Self.playheadPollInterval, repeats: true) { [weak self] in
            guard let self else { return }
            if self.engine.position > placeAtResume + Self.playheadMovedBy { self.scrubTrace.playheadSeenMoving(at: self.clock()) }
            if !self.scrubTrace.awaitingPlayhead || self.clock() > deadline { self.playheadWatch?.invalidate(); self.refresh() }
        }
        RunLoop.main.add(watch, forMode: .common)
        playheadWatch = watch
    }

    private static let playheadPollInterval: TimeInterval = 0.02
    private static let playheadWatchLimit: TimeInterval = 5
    private static let playheadMovedBy: TimeInterval = 0.03

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
