import Foundation

/// One transcribed word with the stretch of the song it was sung in, in seconds from the start of the file.
package struct TimedWord: Codable, Equatable, Sendable {
    package var text: String
    package var start: Double
    package var end: Double
    /// The engine's own confidence in the word, 0 to 1, when it gives one.
    package var confidence: Double?

    package init(_ text: String, start: Double, end: Double, confidence: Double? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

/// A line of lyrics as shown: a run of words that are sung together.
package struct LyricLine: Codable, Equatable, Sendable, Identifiable {
    package var id: Int
    package var words: [TimedWord]

    package init(id: Int, words: [TimedWord]) {
        self.id = id
        self.words = words
    }

    package var start: Double { words.first?.start ?? 0 }
    package var end: Double { words.last?.end ?? 0 }
    package var text: String { words.map(\.text).joined(separator: " ") }
    /// The lowest confidence among the line's words; nil when no word carries one.
    package var confidence: Double? { words.compactMap(\.confidence).min() }
}

/// Which transcription engine made a sheet.
package enum LyricEngine: String, Codable, Sendable, CaseIterable {
    case speechAnalyzer
    case whisperKit

    package var displayName: String {
        switch self {
        case .speechAnalyzer: "Apple Speech"
        case .whisperKit: "Whisper"
        }
    }
}

/// The lyrics of one song as transcribed on this device: a machine guess, kept so it is made once per song.
package struct LyricSheet: Codable, Equatable, Sendable {
    package static let formatVersion = 1

    package var songKey: String
    package var engine: LyricEngine
    package var separated: Bool
    package var language: String?
    package var lines: [LyricLine]
    package var madeAt: Date
    package var version: Int

    package init(songKey: String, engine: LyricEngine, separated: Bool, language: String?, lines: [LyricLine],
                 madeAt: Date = Date(), version: Int = LyricSheet.formatVersion) {
        self.songKey = songKey
        self.engine = engine
        self.separated = separated
        self.language = language
        self.lines = lines
        self.madeAt = madeAt
        self.version = version
    }

    package var words: [TimedWord] { lines.flatMap(\.words) }
}

/// What an engine must do to transcribe a song for the lyrics panel. Engines live outside the core (they need
/// system speech or machine-learning frameworks); the core only sees timed words.
package protocol LyricTranscribing: Sendable {
    var engine: LyricEngine { get }
    /// Timed words for the whole file, in order. `language` is a BCP-47 tag when known, nil to let the engine decide.
    func transcribe(_ url: URL, language: String?) async throws -> [TimedWord]
}

/// Separates the vocals from a song so the transcriber hears less music. Returns the vocals as an audio file.
package protocol VocalSeparating: Sendable {
    func separateVocals(from url: URL, into directory: URL) async throws -> URL
}

/// Finds the stretches of a file in which someone is singing, so words outside them can be dropped.
package protocol VocalActivityDetecting: Sendable {
    func vocalRanges(in url: URL) async throws -> [ClosedRange<Double>]
}

package enum LyricsError: Error, Equatable {
    case nothingTranscribed
    case unsupported(String)
}
