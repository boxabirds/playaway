import Foundation
import AVFoundation

/// One loaded file. The engine owns at most one at a time.
package protocol AudioPlayerHandle: AnyObject {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }
    /// Effective output gain: zero when muted.
    var gain: Float { get set }
    var onFinish: (() -> Void)? { get set }
    func start() -> Bool
    func pause()
    func stop()
    /// Ramps the gain to `target` over `duration`, so that starting in the middle of a waveform cannot click.
    func fadeGain(to target: Float, over duration: TimeInterval)
}

extension AudioPlayerHandle {
    package func fadeGain(to target: Float, over duration: TimeInterval) { gain = target }
}

/// Seam that lets tests replace the audio output with a recording sink.
package protocol AudioBackend {
    func makePlayer(for url: URL) throws -> AudioPlayerHandle
}

package struct AVAudioPlayerBackend: AudioBackend {
    package init() {}
    package func makePlayer(for url: URL) throws -> AudioPlayerHandle {
        try AVAudioPlayerHandle(url: url)
    }
}

/// Audio is rendered by AVFoundation's own thread; nothing here runs in a render callback.
package final class AVAudioPlayerHandle: NSObject, AudioPlayerHandle, AVAudioPlayerDelegate {
    private let player: AVAudioPlayer
    package var onFinish: (() -> Void)?

    package init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        player.delegate = self
        player.prepareToPlay()
    }

    package var duration: TimeInterval { player.duration }

    package var currentTime: TimeInterval {
        get { player.currentTime }
        set { player.currentTime = newValue }
    }

    package var gain: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    package func fadeGain(to target: Float, over duration: TimeInterval) { player.setVolume(target, fadeDuration: duration) }

    package func start() -> Bool { player.play() }
    package func pause() { player.pause() }

    package func stop() {
        player.delegate = nil
        player.stop()
    }

    package func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}
