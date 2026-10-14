import Foundation

/// Where the person can be: the Playlists screen, or one playlist.
package enum NavigationDestination<ID: Hashable>: Hashable {
    case playlists
    case playlist(ID)
}

/// One browser-style history for the whole app. Going somewhere records where the person was; going back returns
/// there. The player card opening or closing is not a navigation and never reaches this. There is no depth limit,
/// no Forward and no persistence, because none was decided.
package struct NavigationHistory<ID: Hashable>: Equatable {
    package typealias Destination = NavigationDestination<ID>

    package private(set) var current: Destination
    private var left: [Destination]

    /// A new history at the Playlists screen with nothing to go back to.
    package init() {
        current = .playlists
        left = []
    }

    /// A history for a stack of playlists shown above the Playlists screen, oldest first.
    package init(playlists trail: [ID]) {
        guard let last = trail.last else { current = .playlists; left = []; return }
        current = .playlist(last)
        left = [.playlists] + trail.dropLast().map { .playlist($0) }
    }

    /// Where Back would go, nil at the start.
    package var previous: Destination? { left.last }
    package var canGoBack: Bool { !left.isEmpty }

    /// The playlists above the Playlists screen, oldest first: the shape a navigation stack shows.
    package var playlistTrail: [ID] {
        (left + [current]).compactMap { if case .playlist(let id) = $0 { return id } else { return nil } }
    }

    /// Going to the destination already shown records nothing. Any other destination, including one visited
    /// earlier, records the one being left.
    package mutating func navigate(to destination: Destination) {
        guard destination != current else { return }
        left.append(current)
        current = destination
    }

    /// Returns to the destination most recently left, or nil when there is nothing to go back to.
    @discardableResult
    package mutating func back() -> Destination? {
        guard let destination = left.popLast() else { return nil }
        current = destination
        return destination
    }
}
