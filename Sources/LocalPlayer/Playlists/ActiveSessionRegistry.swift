import Foundation

protocol SessionEnding: AnyObject {
    func end()
}

/// Only one thing plays at a time: beginning a session ends whichever session was active.
final class ActiveSessionRegistry {
    private(set) weak var active: SessionEnding?

    func begin(_ session: SessionEnding) {
        if let current = active, current !== session {
            current.end()
        }
        active = session
    }

    /// Ends the active session, if any. Used when a single audio file is opened.
    func endActive() {
        let session = active
        active = nil
        session?.end()
    }

    func didEnd(_ session: SessionEnding) {
        if active === session { active = nil }
    }
}
