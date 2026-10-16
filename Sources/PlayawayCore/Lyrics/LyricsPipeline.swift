import Foundation

/// Makes a sheet for one song: separate the vocals (when asked), transcribe, drop words sung over nothing, group into
/// lines, keep. One song at a time; the caller runs it off the main thread and never waits on it for playback.
package actor LyricsPipeline {
    package enum Stage: Equatable, Sendable {
        case separating
        case transcribing
        case finishing
    }

    private let transcriber: any LyricTranscribing
    private let separator: (any VocalSeparating)?
    private let activity: (any VocalActivityDetecting)?
    private let store: any LyricSheetStoring
    private let workDirectory: URL
    private let breaking: LineBreaking

    package init(transcriber: any LyricTranscribing, separator: (any VocalSeparating)?, activity: (any VocalActivityDetecting)?,
                 store: any LyricSheetStoring, workDirectory: URL, breaking: LineBreaking = .default) {
        self.transcriber = transcriber
        self.separator = separator
        self.activity = activity
        self.store = store
        self.workDirectory = workDirectory
        self.breaking = breaking
    }

    /// The finished sheet, also saved in the store. Throws `LyricsError.nothingTranscribed` when no word survived.
    package func makeSheet(for url: URL, songKey: String, language: String?,
                           progress: @Sendable (Stage) -> Void = { _ in }) async throws -> LyricSheet {
        var source = url
        var separated = false
        if let separator {
            progress(.separating)
            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            source = try await separator.separateVocals(from: url, into: workDirectory)
            separated = true
        }
        progress(.transcribing)
        var words = try await transcriber.transcribe(source, language: language)
        progress(.finishing)
        if let activity {
            let ranges = try await activity.vocalRanges(in: source)
            words = gated(words, toVocalRanges: ranges)
        }
        let lines = lyricLines(from: words, breaking: breaking)
        guard !lines.isEmpty else { throw LyricsError.nothingTranscribed }
        let sheet = LyricSheet(songKey: songKey, engine: transcriber.engine, separated: separated, language: language, lines: lines)
        try store.save(sheet)
        if separated { try? FileManager.default.removeItem(at: source) }
        return sheet
    }
}
