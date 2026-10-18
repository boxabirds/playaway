import Foundation

/// Where each song of a playlist was last found on this device, remembered so that drawing a row does not touch the file
/// system again. A song that was found stays found until something that could change the answer happens (`removeAll`). A
/// song that was NOT found is remembered only briefly: before this, every redraw looked for every missing song again, which
/// for a playlist with hundreds of them was hundreds of file-system searches per redraw; but a file can also arrive (iCloud
/// finishes a download, the person copies it in), so the answer must not be kept for long.
package final class ResolutionCache {
    package enum Lookup: Equatable {
        case found(URL)
        case unfound
        /// Nothing remembered (never looked for, or the remembered "not found" has expired): look now.
        case unknown
    }

    package static let defaultUnfoundLifetime: TimeInterval = 2

    private var found: [UUID: URL] = [:]
    private var unfoundAt: [UUID: Date] = [:]
    private let unfoundLifetime: TimeInterval
    private let clock: () -> Date

    package init(unfoundLifetime: TimeInterval = ResolutionCache.defaultUnfoundLifetime, clock: @escaping () -> Date = Date.init) {
        self.unfoundLifetime = unfoundLifetime
        self.clock = clock
    }

    package func lookup(_ id: UUID) -> Lookup {
        if let url = found[id] { return .found(url) }
        if let at = unfoundAt[id] {
            if clock().timeIntervalSince(at) < unfoundLifetime { return .unfound }
            unfoundAt[id] = nil
        }
        return .unknown
    }

    /// Remembers the answer of a search: the file's place, or nil for "not found".
    package func store(_ id: UUID, url: URL?) {
        if let url { found[id] = url; unfoundAt[id] = nil } else { found[id] = nil; unfoundAt[id] = clock() }
    }

    package func removeAll() { found.removeAll(); unfoundAt.removeAll() }
}
