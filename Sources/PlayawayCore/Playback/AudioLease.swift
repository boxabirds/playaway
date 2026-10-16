import Foundation

/// The one permission to make a sound. An engine has exactly one lease, and whichever sound holds it is the only sound
/// that can be heard. Taking the lease for a new sound silences the holder first, in the same call and before anything
/// new starts, so two sounds can never overlap: not a song and the scrub loop, and not two songs.
package final class AudioLease {
    package enum Holder: Equatable { case song, preview }

    package private(set) var holder: Holder?
    private var silence: (() -> Void)?

    package init() {}

    /// Makes `holder` the sound that may be heard, silencing whatever held the lease before. `silence` is how the new
    /// holder is silenced when it loses the lease in its turn.
    package func take(_ holder: Holder, silencedBy silence: @escaping () -> Void) {
        vacate()
        self.holder = holder
        self.silence = silence
    }

    /// The holder has fallen silent by itself (paused, stopped or finished), so there is nothing to silence.
    package func release(_ holder: Holder) {
        guard self.holder == holder else { return }
        self.holder = nil
        silence = nil
    }

    /// Silences the holder, if any, and leaves the lease free.
    package func vacate() {
        let silence = self.silence
        holder = nil
        self.silence = nil
        silence?()
    }
}
