import Foundation
import os

/// A trace for the end-to-end tests to read with `log show --predicate 'subsystem == "com.localplayer.trace"'`.
/// Debug builds only; a release build keeps nothing of it.
enum DebugTrace {
    static let subsystem = "com.localplayer.trace"
    #if DEBUG
    private static let logger = Logger(subsystem: subsystem, category: "trace")
    #endif

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        logger.notice("\(text, privacy: .public)")
        #endif
    }
}
