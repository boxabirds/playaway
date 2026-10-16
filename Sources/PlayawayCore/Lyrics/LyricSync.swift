import Foundation

/// Which line to light up for a playback position. Pure functions of the sheet and the position: the position is read
/// live from the engine by the caller, never stored here.
package enum LyricSync {
    /// Lines are shown this much before they are sung, so the eye arrives with the voice.
    package static let lead: Double = 0.1
    /// After a line ends, a silence this long counts as an instrumental passage.
    package static let instrumentalGap: Double = 4

    /// The last line that has started by `position`, or nil before the first line.
    package static func currentLineIndex(in lines: [LyricLine], at position: Double) -> Int? {
        let at = position + lead
        var found: Int?
        for (index, line) in lines.enumerated() where line.start <= at { found = index }
        return found
    }

    /// True when the song is between lines for long enough that nothing is being sung.
    package static func isInstrumental(in lines: [LyricLine], at position: Double) -> Bool {
        guard let index = currentLineIndex(in: lines, at: position) else {
            return (lines.first?.start ?? 0) - position > instrumentalGap
        }
        let line = lines[index]
        guard position > line.end else { return false }
        let nextStart = index + 1 < lines.count ? lines[index + 1].start : .infinity
        return nextStart - line.end > instrumentalGap
    }

    /// How many of the line's words have started by `position`, as a fraction of the line.
    package static func progress(in line: LyricLine, at position: Double) -> Double {
        guard !line.words.isEmpty else { return 0 }
        let sung = line.words.filter { $0.start <= position + lead }.count
        return Double(sung) / Double(line.words.count)
    }
}
