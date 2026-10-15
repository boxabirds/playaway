import Foundation
import Combine

package enum PlayResult: Equatable {
    case playing
    case noOutputDevice
    case failed(String)
}

package enum TransportState: Equatable {
    case idle, playing, paused
}

package enum EngineEvent: Equatable {
    /// Transport state, position basis or loaded file changed.
    case stateChanged
    /// The file played to its end by itself.
    case finished(URL)
    /// The person (or a script) stopped playback.
    case stopped
    /// Volume or mute changed.
    case levelChanged
}

package enum PrepareResult: Equatable {
    case ready
    case failed(String)
    case noOutputDevice
}

package protocol PlaybackEngine: AnyObject {
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
    /// Loads a file paused at `seconds`, without making a sound, so that what is shown (the title, the length, the place) is
    /// exactly what the engine holds, as for any other paused song.
    func prepare(_ url: URL, at seconds: Double) -> PrepareResult
    func pause()
    func resume()
    func stop()
    func seek(toSeconds seconds: Double) -> Bool
    func setMuted(_ muted: Bool)
}
