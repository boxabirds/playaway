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
        commands.playCommand.addTarget { [weak self] _ in self?.run { try $0.transport.play() } ?? .commandFailed }
        commands.pauseCommand.addTarget { [weak self] _ in self?.run { try $0.transport.pause() } ?? .commandFailed }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in self?.run { $0.transport.playPause() } ?? .commandFailed }
        commands.nextTrackCommand.addTarget { [weak self] _ in self?.run { try $0.transport.next() } ?? .commandFailed }
        commands.previousTrackCommand.addTarget { [weak self] _ in self?.run { try $0.transport.previous() } ?? .commandFailed }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return self?.run { try $0.transport.seek(toSeconds: e.positionTime) } ?? .commandFailed
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated { self?.interruption(n) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated { self?.routeChange(n) }
        })
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
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        center.nowPlayingInfo = info
    }
}
