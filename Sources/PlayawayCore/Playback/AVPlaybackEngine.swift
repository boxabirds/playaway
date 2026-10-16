import Foundation
import Combine

/// Plays one file at a time. All calls are made on the main thread.
///
/// Every sound the app makes is made here: the song, through an `AudioPlayerHandle`, and the scrub loop, through the
/// `LoopingPreviewing`. One `AudioLease` decides which of them may be heard; whoever takes it silences the other first,
/// so there is no call in or out of this class after which two sounds play together.
package final class AVPlaybackEngine: PlaybackEngine {
    private let backend: AudioBackend
    private let devices: OutputDeviceProviding
    private let settings: VolumeSettingsStoring
    private let preview: LoopingPreviewing
    private let lease = AudioLease()
    private let subject = PassthroughSubject<EngineEvent, Never>()

    private var player: AudioPlayerHandle?
    private var generation = 0
    package private(set) var state: TransportState = .idle
    package private(set) var currentURL: URL?
    private var storedVolume: Double
    package private(set) var isMuted: Bool

    package var events: AnyPublisher<EngineEvent, Never> { subject.eraseToAnyPublisher() }

    /// Initial volume and mute are applied here, before any window or view exists.
    package init(backend: AudioBackend = AVAudioPlayerBackend(),
         devices: OutputDeviceProviding = DefaultOutputDevices.make(),
         settings: VolumeSettingsStoring = VolumeSettingsStore(),
         preview: LoopingPreviewing = AVLoopingPreview()) {
        self.backend = backend
        self.devices = devices
        self.settings = settings
        self.preview = preview
        let loaded = settings.load()
        storedVolume = loaded.volume
        isMuted = loaded.isMuted
    }

    package var isPlaying: Bool { state == .playing }
    package var isPaused: Bool { state == .paused }
    package var position: Double { state == .idle ? 0 : (player?.currentTime ?? 0) }
    package var duration: Double { state == .idle ? 0 : (player?.duration ?? 0) }

    package var volume: Double {
        get { storedVolume }
        set { setVolume(newValue) }
    }

    package func play(_ url: URL) -> PlayResult {
        guard devices.hasOutputDevice else { return .noOutputDevice }
        let newPlayer: AudioPlayerHandle
        do {
            newPlayer = try backend.makePlayer(for: url)
        } catch {
            return .failed(error.localizedDescription)
        }
        generation += 1
        let token = generation
        newPlayer.onFinish = { [weak self] in self?.trackFinished(token: token, url: url) }
        newPlayer.gain = effectiveGain
        let wasPlaying = state == .playing
        lease.vacate()                                  // whatever is sounding falls silent before the new song starts
        guard newPlayer.start() else {
            if wasPlaying { resume() }                  // the new file could not start: the old song carries on
            return .failed("The audio output could not start playing this file.")
        }
        let previous = player
        player = newPlayer
        currentURL = url
        state = .playing
        lease.take(.song, silencedBy: songSilencer)
        previous?.onFinish = nil
        previous?.stop()
        subject.send(.stateChanged)
        return .playing
    }

    package func prepare(_ url: URL, at seconds: Double) -> PrepareResult {
        guard devices.hasOutputDevice else { return .noOutputDevice }
        let newPlayer: AudioPlayerHandle
        do {
            newPlayer = try backend.makePlayer(for: url)
        } catch {
            return .failed(error.localizedDescription)
        }
        generation += 1
        let token = generation
        newPlayer.onFinish = { [weak self] in self?.trackFinished(token: token, url: url) }
        newPlayer.gain = effectiveGain
        newPlayer.currentTime = min(max(seconds.isFinite ? seconds : 0, 0), newPlayer.duration)
        lease.vacate()
        let previous = player
        player = newPlayer
        currentURL = url
        state = .paused
        previous?.onFinish = nil
        previous?.stop()
        subject.send(.stateChanged)
        return .ready
    }

    package func pause() {
        guard state == .playing, let player else { return }
        player.pause()
        state = .paused
        lease.release(.song)
        subject.send(.stateChanged)
    }

    package func resume() {
        guard state == .paused, let player else { return }
        lease.take(.song, silencedBy: songSilencer)     // silences the loop, if it was sounding
        guard player.start() else { lease.release(.song); return }
        state = .playing
        subject.send(.stateChanged)
    }

    package func resume(fadingIn duration: TimeInterval) {
        guard state == .paused, let player else { return }
        let target = effectiveGain
        player.gain = 0
        lease.take(.song, silencedBy: songSilencer)
        guard player.start() else { player.gain = target; lease.release(.song); return }
        player.fadeGain(to: target, over: duration)
        state = .playing
        subject.send(.stateChanged)
    }

    package func stop() {
        guard state != .idle else { return }
        lease.vacate()
        generation += 1
        player?.onFinish = nil
        player?.stop()
        player = nil
        currentURL = nil
        state = .idle
        subject.send(.stateChanged)
        subject.send(.stopped)
    }

    package func seek(toSeconds seconds: Double) -> Bool {
        guard state != .idle, let player, seconds.isFinite, seconds >= 0, seconds <= player.duration else {
            return false
        }
        player.currentTime = seconds
        subject.send(.stateChanged)
        return true
    }

    package func setMuted(_ muted: Bool) {
        isMuted = muted
        player?.gain = effectiveGain
        settings.saveMuted(muted)
        subject.send(.levelChanged)
    }

    // MARK: The scrub loop

    package var isPreviewing: Bool { lease.holder == .preview }

    package func startPreviewLoop(at seconds: Double, length: TimeInterval) -> Bool {
        guard state != .idle, let url = currentURL else { return false }
        lease.take(.preview) { [weak self] in self?.preview.stop() }     // the song falls silent (paused) here
        guard preview.start(url: url, at: seconds, length: length) else {
            lease.release(.preview)
            return false
        }
        subject.send(.stateChanged)
        return true
    }

    @discardableResult
    package func stopPreviewLoop() -> Double? {
        guard lease.holder == .preview else { return nil }
        let place = preview.stop()
        lease.release(.preview)
        subject.send(.stateChanged)
        return place
    }

    /// How the song is silenced when something else takes the lease: paused, so that it can carry on afterwards.
    private var songSilencer: () -> Void { { [weak self] in self?.pause() } }

    private func setVolume(_ value: Double) {
        guard value.isFinite else { return }
        storedVolume = min(max(value, volumeMinimum), volumeMaximum)
        player?.gain = effectiveGain
        settings.saveVolume(storedVolume)
        subject.send(.levelChanged)
    }

    private var effectiveGain: Float { isMuted ? 0 : Float(storedVolume) }

    private func trackFinished(token: Int, url: URL) {
        guard token == generation else { return }
        lease.release(.song)
        player?.onFinish = nil
        player = nil
        currentURL = nil
        state = .idle
        subject.send(.stateChanged)
        subject.send(.finished(url))
    }
}
