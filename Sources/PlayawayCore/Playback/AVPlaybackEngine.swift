import Foundation
import Combine

/// Plays one file at a time. All calls are made on the main thread.
package final class AVPlaybackEngine: PlaybackEngine {
    private let backend: AudioBackend
    private let devices: OutputDeviceProviding
    private let settings: VolumeSettingsStoring
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
         settings: VolumeSettingsStoring = VolumeSettingsStore()) {
        self.backend = backend
        self.devices = devices
        self.settings = settings
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
        guard newPlayer.start() else {
            return .failed("The audio output could not start playing this file.")
        }
        let previous = player
        player = newPlayer
        currentURL = url
        state = .playing
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
        subject.send(.stateChanged)
    }

    package func resume() {
        guard state == .paused, let player else { return }
        guard player.start() else { return }
        state = .playing
        subject.send(.stateChanged)
    }

    package func stop() {
        guard state != .idle else { return }
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
        player?.onFinish = nil
        player = nil
        currentURL = nil
        state = .idle
        subject.send(.stateChanged)
        subject.send(.finished(url))
    }
}
