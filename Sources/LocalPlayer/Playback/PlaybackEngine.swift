import Foundation
import Combine

enum PlayResult: Equatable {
    case playing
    case noOutputDevice
    case failed(String)
}

enum TransportState: Equatable {
    case idle, playing, paused
}

enum EngineEvent: Equatable {
    /// Transport state, position basis or loaded file changed.
    case stateChanged
    /// The file played to its end by itself.
    case finished(URL)
    /// The person (or a script) stopped playback.
    case stopped
    /// Volume or mute changed.
    case levelChanged
}

protocol PlaybackEngine: AnyObject {
    var events: AnyPublisher<EngineEvent, Never> { get }
    var state: TransportState { get }
    var isPlaying: Bool { get }
    var isPaused: Bool { get }
    var currentURL: URL? { get }
    var position: Double { get }
    var duration: Double { get }
    var volume: Double { get set }
    var isMuted: Bool { get }

    func play(_ url: URL) -> PlayResult
    func pause()
    func resume()
    func stop()
    func seek(toSeconds seconds: Double) -> Bool
    func setMuted(_ muted: Bool)
}
