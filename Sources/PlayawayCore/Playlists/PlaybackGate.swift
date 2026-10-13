import Foundation

package enum PlayDecision: Equatable {
    case play(URL)
    case refuse
}

package protocol PlaybackGating {
    func decide(for status: TrackStatus) -> PlayDecision
}

/// A missing track is never played, by the person or by automatic play-through.
package struct PlaybackGate: PlaybackGating {
    package init() {}
    package func decide(for status: TrackStatus) -> PlayDecision {
        switch status {
        case .resolved(let url): return .play(url)
        case .missing: return .refuse
        }
    }
}
