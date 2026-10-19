import Foundation

/// The last few things that happened around a drag in the song list, kept in memory so that a person who sees a drag go wrong
/// on their own phone can read them out (Experiments > Drag log) and send them. Nothing is written to disk or sent anywhere.
package final class DragTrace: @unchecked Sendable {
    package static let shared = DragTrace()
    /// How many lines are kept; older ones are dropped.
    package static let capacity = 60

    private let lock = NSLock()
    private var entries: [String] = []
    private let clock: () -> Date
    private let formatter: DateFormatter

    package init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
        formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
    }

    package func record(_ event: String) {
        lock.lock(); defer { lock.unlock() }
        entries.append("\(formatter.string(from: clock())) \(event)")
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    package var lines: [String] { lock.lock(); defer { lock.unlock() }; return entries }
    package func clear() { lock.lock(); entries.removeAll(); lock.unlock() }
    /// All lines as one text, for copying.
    package var text: String { lines.joined(separator: "\n") }
}
