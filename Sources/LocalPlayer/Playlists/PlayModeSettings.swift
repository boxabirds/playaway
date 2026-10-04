import Foundation
import Combine

/// Shuffle (on/off) and Repeat (off/all/one): two independent values shared by every playlist window and
/// saved immediately. If a save fails the new value is kept in memory for this launch.
final class PlayModeSettings: ObservableObject {
    @Published private(set) var shuffleOn: Bool
    @Published private(set) var repeatMode: RepeatMode
    private let store: PlayModeStoring

    /// Fires after a change, so a running session can apply it to its next decision.
    let didChange = PassthroughSubject<Void, Never>()

    init(store: PlayModeStoring = PlayModeStore()) {
        self.store = store
        let loaded = store.load()
        shuffleOn = loaded.shuffle
        repeatMode = loaded.repeatMode
    }

    func toggleShuffle() { setShuffle(!shuffleOn) }
    func cycleRepeat() { setRepeat(repeatMode.next) }

    func setShuffle(_ on: Bool) {
        guard on != shuffleOn else { return }
        shuffleOn = on
        store.saveShuffle(on)
        didChange.send()
    }

    func setRepeat(_ mode: RepeatMode) {
        guard mode != repeatMode else { return }
        repeatMode = mode
        store.saveRepeat(mode)
        didChange.send()
    }
}
