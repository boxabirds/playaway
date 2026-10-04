import Foundation

enum PlayDecision: Equatable {
    case play(URL)
    case refuse
}

protocol PlaybackGating {
    func decide(for status: TrackStatus) -> PlayDecision
}

/// A missing track is never played, by the person or by automatic play-through.
struct PlaybackGate: PlaybackGating {
    func decide(for status: TrackStatus) -> PlayDecision {
        switch status {
        case .resolved(let url): return .play(url)
        case .missing: return .refuse
        }
    }
}
