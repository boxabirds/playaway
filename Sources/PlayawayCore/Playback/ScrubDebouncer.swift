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
            self?.commit(seconds)
        }
    }

    package func finish(at seconds: Double) {
        pending?.cancel()
        pending = nil
        commit(seconds)
    }
}
