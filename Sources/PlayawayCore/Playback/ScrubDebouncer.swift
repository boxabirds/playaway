import Foundation

/// How long a scrub must pause before the player actually moves. Seeking on every finger movement makes the audio stutter.
package let scrubDebounceSeconds: TimeInterval = 0.3

/// Turns a stream of scrub positions into few seeks: a position is committed only after the scrub has paused for
/// `delay`, and the final position is committed straight away when the finger lifts.
@MainActor
package final class ScrubDebouncer {
    private let delay: TimeInterval
    private let commit: (Double) -> Void
    private var pending: Task<Void, Never>?
    /// Where the pause during this drag already sought to, so lifting the finger in the same place does not seek again.
    private var lastCommitted: Double?

    package init(delay: TimeInterval = scrubDebounceSeconds, commit: @escaping (Double) -> Void) {
        self.delay = delay
        self.commit = commit
    }

    package func scrub(to seconds: Double) {
        pending?.cancel()
        let delay = delay
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.lastCommitted = seconds
            self?.commit(seconds)
        }
    }

    /// The finger lifted. A seek is made unless the drag already sought to exactly this place, which would replay the
    /// same short stretch of the song twice.
    package func finish(at seconds: Double) {
        pending?.cancel()
        pending = nil
        defer { lastCommitted = nil }
        if lastCommitted == seconds { return }
        commit(seconds)
    }
}
