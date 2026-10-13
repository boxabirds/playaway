import Foundation
import Combine

/// Shuffle (on/off) and Repeat (off/all/one): two independent values shared by every playlist window and
/// saved immediately. If a save fails the new value is kept in memory for this launch.
package final class PlayModeSettings: ObservableObject {
    @Published package private(set) var shuffleOn: Bool
    @Published package private(set) var repeatMode: RepeatMode
    private let store: PlayModeStoring

    /// Fires after a change, so a running session can apply it to its next decision.
    package let didChange = PassthroughSubject<Void, Never>()

    package init(store: PlayModeStoring = PlayModeStore()) {
        self.store = store
        let loaded = store.load()
        shuffleOn = loaded.shuffle
        repeatMode = loaded.repeatMode
    }

    package func toggleShuffle() { setShuffle(!shuffleOn) }
    package func cycleRepeat() { setRepeat(repeatMode.next) }

    package func setShuffle(_ on: Bool) {
        guard on != shuffleOn else { return }
        shuffleOn = on
        store.saveShuffle(on)
        didChange.send()
    }

    package func setRepeat(_ mode: RepeatMode) {
        guard mode != repeatMode else { return }
        repeatMode = mode
        store.saveRepeat(mode)
        didChange.send()
    }
}
