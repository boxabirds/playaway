import Foundation

/// A timestamped record of the last slider drag, so that what the touch events really did on a phone can be read off the
/// screen: when the finger went down, how often and until when it moved, when the lift was reported, when playback was
/// asked to resume and when the playhead was first seen moving again. Times are seconds since the finger went down.
package struct ScrubTrace {
    package enum End: Equatable { case lift, safetyTimer }

    private var start: Date?
    private var moves = 0
    private var lastMove: TimeInterval?
    private var ended: (TimeInterval, End)?
    private var resumeCalled: TimeInterval?
    private var wasPlaying = false
    private var playheadMoving: TimeInterval?

    package init() {}

    package var isEmpty: Bool { start == nil }
    /// True once a drag has ended and the playhead has not yet been seen moving.
    package var awaitingPlayhead: Bool { resumeCalled != nil && playheadMoving == nil }

    package mutating func fingerDown(at now: Date, wasPlaying: Bool) {
        self = ScrubTrace()
        start = now
        self.wasPlaying = wasPlaying
    }

    package mutating func moved(at now: Date) {
        guard let start else { return }
        moves += 1
        lastMove = now.timeIntervalSince(start)
    }

    package mutating func end(_ how: End, at now: Date) {
        guard let start, ended == nil else { return }
        ended = (now.timeIntervalSince(start), how)
    }

    package mutating func resumeRequested(at now: Date) {
        guard let start else { return }
        resumeCalled = now.timeIntervalSince(start)
    }

    package mutating func playheadSeenMoving(at now: Date) {
        guard let start, playheadMoving == nil else { return }
        playheadMoving = now.timeIntervalSince(start)
    }

    private func seconds(_ value: TimeInterval?) -> String { value.map { String(format: "%.2f", $0) } ?? "–" }

    package var summary: String {
        guard start != nil else { return "no drag yet" }
        let how = ended.map { $0.1 == .lift ? "lift" : "SAFETY TIMER (no lift seen)" } ?? "–"
        return "down 0 · \(moves) moves, last \(seconds(lastMove)) · \(how) \(seconds(ended?.0)) · "
            + "resume \(wasPlaying ? seconds(resumeCalled) : "n/a (was paused)") · playhead moving \(seconds(playheadMoving))"
    }
}
