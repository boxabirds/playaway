import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import PlayawayCore

/// Lock Screen, Control Center and headphone controls, plus audio interruptions and route changes.
@MainActor
final class NowPlayingCenter {
    private weak var model: AppModel?
    private var observers: [NSObjectProtocol] = []
    private var resumeAfterInterruption = false

    func attach(model: AppModel) {
        self.model = model
        let commands = MPRemoteCommandCenter.shared()
        Self.register(commands.playCommand, on: self) { me, _ in me.run { try $0.transport.play() } }
        Self.register(commands.pauseCommand, on: self) { me, _ in me.run { try $0.transport.pause() } }
        Self.register(commands.togglePlayPauseCommand, on: self) { me, _ in me.run { $0.transport.playPause() } }
        Self.register(commands.nextTrackCommand, on: self) { me, _ in me.run { try $0.transport.next() } }
        Self.register(commands.previousTrackCommand, on: self) { me, _ in me.run { try $0.transport.previous() } }
        Self.register(commands.changePlaybackPositionCommand, on: self) { me, event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return me.run { try $0.transport.seek(toSeconds: e.positionTime) }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            nonisolated(unsafe) let note = n          // delivered on the main queue, which is the main actor
            MainActor.assumeIsolated { self?.interruption(note) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            nonisolated(unsafe) let note = n
            MainActor.assumeIsolated { self?.routeChange(note) }
        })
    }

    /// A remote command's handler must not be a main-actor closure: the system is free to call it on any thread, and a
    /// main-actor closure called elsewhere stops the app. This is made outside the actor and moves the work onto the main
    /// thread itself (waiting for it, because the system wants the answer back).
    nonisolated private static func register(_ command: MPRemoteCommand, on center: NowPlayingCenter,
                                             _ body: @escaping @MainActor @Sendable (NowPlayingCenter, MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        command.addTarget { [weak center] event in
            nonisolated(unsafe) let event = event
            let work: @MainActor () -> MPRemoteCommandHandlerStatus = {
                guard let center else { return .commandFailed }
                return body(center, event)
            }
            if Thread.isMainThread { return MainActor.assumeIsolated(work) }
            return DispatchQueue.main.sync { MainActor.assumeIsolated(work) }
        }
    }

    private func run(_ body: (AppModel) throws -> Void) -> MPRemoteCommandHandlerStatus {
        guard let model else { return .commandFailed }
        do { try body(model); return .success } catch { return .commandFailed }
    }

    private func interruption(_ n: Notification) {
        guard let model, let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            resumeAfterInterruption = model.transport.state == .playing
            try? model.transport.pause()
        case .ended:
            let options = (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init) ?? []
            if resumeAfterInterruption, options.contains(.shouldResume) { try? model.transport.play() }
            resumeAfterInterruption = false
        @unknown default: break
        }
    }

    /// Unplugging headphones pauses, as the system's own players do.
    private func routeChange(_ n: Notification) {
        guard let model, let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
        try? model.transport.pause()
    }

    func update() {
        guard let model else { return }
        let center = MPNowPlayingInfoCenter.default()
        guard model.transport.state != .idle else { center.nowPlayingInfo = nil; return }
        let meta = model.metadata
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: meta?.title ?? model.transport.nowPlaying,
            MPMediaItemPropertyPlaybackDuration: model.engine.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: model.engine.position,
            MPNowPlayingInfoPropertyPlaybackRate: model.transport.state == .playing ? 1.0 : 0.0
        ]
        if let artist = meta?.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = meta?.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let name = model.activeSession?.name { info[MPMediaItemPropertyAlbumTitle] = meta?.album ?? name }
        if let data = meta?.artworkData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = nowPlayingArtwork(image)
        }
        center.nowPlayingInfo = info
    }
}

/// The system asks for the artwork on its own queue, so the handler is made here, outside the main actor; a closure made
/// in a main-actor method would stop the app when called there. The image is only read.
private func nowPlayingArtwork(_ image: UIImage) -> MPMediaItemArtwork {
    nonisolated(unsafe) let picture = image
    return MPMediaItemArtwork(boundsSize: image.size) { _ in picture }
}
