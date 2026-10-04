import Foundation
import AVFoundation

/// One loaded file. The engine owns at most one at a time.
protocol AudioPlayerHandle: AnyObject {
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }
    /// Effective output gain: zero when muted.
    var gain: Float { get set }
    var onFinish: (() -> Void)? { get set }
    func start() -> Bool
    func pause()
    func stop()
}

/// Seam that lets tests replace the audio output with a recording sink.
protocol AudioBackend {
    func makePlayer(for url: URL) throws -> AudioPlayerHandle
}

struct AVAudioPlayerBackend: AudioBackend {
    func makePlayer(for url: URL) throws -> AudioPlayerHandle {
        try AVAudioPlayerHandle(url: url)
    }
}

/// Audio is rendered by AVFoundation's own thread; nothing here runs in a render callback.
final class AVAudioPlayerHandle: NSObject, AudioPlayerHandle, AVAudioPlayerDelegate {
    private let player: AVAudioPlayer
    var onFinish: (() -> Void)?

    init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        player.delegate = self
        player.prepareToPlay()
    }

    var duration: TimeInterval { player.duration }

    var currentTime: TimeInterval {
        get { player.currentTime }
        set { player.currentTime = newValue }
    }

    var gain: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    func start() -> Bool { player.play() }
    func pause() { player.pause() }

    func stop() {
        player.delegate = nil
        player.stop()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}
