import Foundation

package enum RepeatMode: String, CaseIterable, Equatable {
    case off, all, one

    package var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

package enum Next: Equatable {
    case play(Track)
    case stop
    /// Leave playback exactly as it is.
    case stay
}

package enum PlaybackEvent: Equatable {
    case start, trackFinished, skipForward, skipBackward
}

/// What the decider needs to know. `pass` is the shuffle pass being played (empty when none yet).
package struct AdvanceContext {
    package init(playlist: Playlist, current: Track?, repeatMode: RepeatMode, shuffleOn: Bool, pass: [Track], shuffler: ShuffleOrdering, startedOrder: [Track] = []) {
        self.playlist = playlist
        self.current = current
        self.repeatMode = repeatMode
        self.shuffleOn = shuffleOn
        self.pass = pass
        self.shuffler = shuffler
        self.startedOrder = startedOrder
    }
    package let playlist: Playlist
    package let current: Track?
    package let repeatMode: RepeatMode
    package let shuffleOn: Bool
    package let pass: [Track]
    package let shuffler: ShuffleOrdering
    /// The order `current` was started in. Lets the decider carry on from where `current` was if it has since
    /// been removed from the playlist.
    package var startedOrder: [Track] = []
}

package struct Advance: Equatable {
    package init(next: Next, newPass: [Track]?) {
        self.next = next
        self.newPass = newPass
    }
    package let next: Next
    /// Non-nil when the decision built a new shuffle pass that the caller must keep.
    package let newPass: [Track]?
}

package protocol AdvanceDeciding {
    func advance(event: PlaybackEvent, context: AdvanceContext) -> Advance
}

/// Pure decision logic for what plays next. Skipping unreadable or missing tracks is the player's job:
/// it asks again.
package struct AdvanceDecider: AdvanceDeciding {
    package init() {}
    package func advance(event: PlaybackEvent, context: AdvanceContext) -> Advance {
        let tracks = context.playlist.tracks
        guard !tracks.isEmpty else {
            return Advance(next: event == .skipBackward ? .stay : .stop, newPass: nil)
        }

        var newPass: [Track]?
        var order = tracks
        if context.shuffleOn {
            order = Self.reconciled(pass: context.pass, with: tracks)
            if order.isEmpty || event == .start {
                order = context.shuffler.pass(for: context.playlist, startingWith: nil)
                newPass = order
            }
        }
        let index = context.current.flatMap { current in order.firstIndex { $0.id == current.id } }
        let removedSlot = index == nil ? Self.slotOfRemovedCurrent(in: order, context: context) : nil

        switch event {
        case .start:
            return Advance(next: .play(order[0]), newPass: newPass)

        case .trackFinished:
            if context.repeatMode == .one, let current = context.current, index != nil {
                return Advance(next: .play(current), newPass: newPass)
            }
            return forward(order: order, index: index, removedSlot: removedSlot, context: context, newPass: newPass)

        case .skipForward:
            return forward(order: order, index: index, removedSlot: removedSlot, context: context, newPass: newPass)

        case .skipBackward:
            guard let before = index ?? removedSlot else { return Advance(next: .stay, newPass: newPass) }
            if before > 0 { return Advance(next: .play(order[before - 1]), newPass: newPass) }
            guard context.repeatMode != .off else { return Advance(next: .stay, newPass: newPass) }
            return Advance(next: .play(order[order.count - 1]), newPass: newPass)
        }
    }

    private func forward(order: [Track], index: Int?, removedSlot: Int?, context: AdvanceContext,
                         newPass: [Track]?) -> Advance {
        let nextIndex: Int
        if let index {
            nextIndex = index + 1
        } else if let removedSlot {
            nextIndex = removedSlot
        } else {
            return Advance(next: .stop, newPass: newPass)
        }
        if nextIndex < order.count {
            return Advance(next: .play(order[nextIndex]), newPass: newPass)
        }
        guard context.repeatMode != .off else { return Advance(next: .stop, newPass: newPass) }
        if context.shuffleOn {
            let fresh = context.shuffler.pass(for: context.playlist, startingWith: nil)
            return Advance(next: fresh.first.map { .play($0) } ?? .stop, newPass: fresh)
        }
        return Advance(next: .play(order[0]), newPass: newPass)
    }

    /// Where the removed current track would sit in `order`: the number of tracks that came before it and are
    /// still there. The track now at that position is the one that followed it. Nil when there is no way to know.
    private static func slotOfRemovedCurrent(in order: [Track], context: AdvanceContext) -> Int? {
        guard let current = context.current,
              let position = context.startedOrder.firstIndex(where: { $0.id == current.id }) else { return nil }
        let present = Set(order.map(\.id))
        return context.startedOrder[..<position].filter { present.contains($0.id) }.count
    }

    /// Keeps the pass in step with edits made while it plays: removed tracks drop out, new ones join the end.
    private static func reconciled(pass: [Track], with tracks: [Track]) -> [Track] {
        guard !pass.isEmpty else { return [] }
        let present = Set(tracks.map(\.id))
        var result = pass.filter { present.contains($0.id) }
        let known = Set(result.map(\.id))
        result.append(contentsOf: tracks.filter { !known.contains($0.id) })
        return result
    }
}
