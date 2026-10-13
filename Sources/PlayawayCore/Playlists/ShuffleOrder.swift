import Foundation

package protocol ShuffleOrdering {
    func pass(for playlist: Playlist, startingWith first: Track?) -> [Track]
}

/// A shuffle pass is a random permutation in which every track appears once. The playlist itself is read-only
/// here, so the stored order is never changed. The generator is injected so tests are deterministic.
package struct ShuffleOrder: ShuffleOrdering {
    private let makeGenerator: () -> any RandomNumberGenerator

    package init(makeGenerator: @escaping () -> any RandomNumberGenerator = { SystemRandomNumberGenerator() }) {
        self.makeGenerator = makeGenerator
    }

    package func pass(for playlist: Playlist, startingWith first: Track?) -> [Track] {
        var generator = makeGenerator()
        var rest = playlist.tracks
        var head: [Track] = []
        if let first, let index = rest.firstIndex(where: { $0.id == first.id }) {
            head = [rest.remove(at: index)]
        }
        rest.shuffle(using: &generator)
        return head + rest
    }
}

/// A seedable generator for deterministic shuffle tests (SplitMix64).
package struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    private static let increment: UInt64 = 0x9E3779B97F4A7C15
    private static let mixOne: UInt64 = 0xBF58476D1CE4E5B9
    private static let mixTwo: UInt64 = 0x94D049BB133111EB
    private static let shiftOne: UInt64 = 30
    private static let shiftTwo: UInt64 = 27
    private static let shiftThree: UInt64 = 31

    package init(seed: UInt64) { state = seed }

    package mutating func next() -> UInt64 {
        state &+= Self.increment
        var z = state
        z = (z ^ (z >> Self.shiftOne)) &* Self.mixOne
        z = (z ^ (z >> Self.shiftTwo)) &* Self.mixTwo
        return z ^ (z >> Self.shiftThree)
    }
}
