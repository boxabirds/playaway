import Foundation

/// How words are grouped into lines for display.
package struct LineBreaking: Equatable, Sendable {
    /// A silence longer than this between two words starts a new line.
    package var pauseBreak: Double = 0.6
    /// A shorter silence still starts a new line when the word before it ends a sentence.
    package var sentencePause: Double = 0.2
    /// A line is not allowed to grow past this many characters.
    package var maxCharacters: Int = 42
    /// Stretches of the song (from structure analysis) that a line never crosses, when known.
    package var phrases: [ClosedRange<Double>] = []

    package init() {}
    package static let `default` = LineBreaking()
}

private let sentenceEnders: Set<Character> = [".", "!", "?"]

/// Groups timed words into lines: a new line at a long pause, at a sentence end followed by a short pause, when the
/// line would get too long to read at a glance, or when the next word belongs to another musical phrase.
package func lyricLines(from words: [TimedWord], breaking options: LineBreaking = .default) -> [LyricLine] {
    var lines: [LyricLine] = []
    var current: [TimedWord] = []
    var currentLength = 0

    func close() {
        guard !current.isEmpty else { return }
        lines.append(LyricLine(id: lines.count, words: current))
        current = []
        currentLength = 0
    }

    for word in words {
        let trimmed = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let cleaned = TimedWord(trimmed, start: word.start, end: word.end, confidence: word.confidence)
        if let last = current.last {
            let gap = cleaned.start - last.end
            let endsSentence = last.text.last.map { sentenceEnders.contains($0) } ?? false
            let tooLong = currentLength + 1 + cleaned.text.count > options.maxCharacters
            let crossesPhrase = phrase(of: last.start, in: options.phrases) != phrase(of: cleaned.start, in: options.phrases)
                && phrase(of: cleaned.start, in: options.phrases) != nil
            if gap > options.pauseBreak || (endsSentence && gap > options.sentencePause) || tooLong || crossesPhrase {
                close()
            }
        }
        current.append(cleaned)
        currentLength += (currentLength == 0 ? 0 : 1) + cleaned.text.count
    }
    close()
    return lines
}

private func phrase(of time: Double, in phrases: [ClosedRange<Double>]) -> Int? {
    phrases.firstIndex { $0.contains(time) }
}
