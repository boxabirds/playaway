import XCTest
@testable import PlayawayCore

private func word(_ text: String, _ start: Double, _ end: Double, c: Double? = nil) -> TimedWord {
    TimedWord(text, start: start, end: end, confidence: c)
}

/// Grouping words into lines for display.
final class LyricLinesTests: XCTestCase {
    func testALongPauseStartsANewLine() {
        let lines = lyricLines(from: [word("Driving", 7, 8.7), word("down", 8.7, 9.1), word("Watching", 15, 16.6), word("the", 16.6, 16.9)])
        XCTAssertEqual(lines.map(\.text), ["Driving down", "Watching the"])
        XCTAssertEqual(lines.map(\.id), [0, 1])
        XCTAssertEqual(lines[1].start, 15); XCTAssertEqual(lines[1].end, 16.9)
    }

    func testASentenceEndFollowedByAShortPauseStartsANewLine() {
        let lines = lyricLines(from: [word("waves.", 12, 13.4), word("Watching", 13.7, 14)])
        XCTAssertEqual(lines.map(\.text), ["waves.", "Watching"])
        let noPause = lyricLines(from: [word("waves.", 12, 13.4), word("Watching", 13.5, 14)])
        XCTAssertEqual(noPause.map(\.text), ["waves. Watching"], "a sentence end with no pause is a mid-line full stop")
    }

    func testALineNeverGrowsPastTheReadableLength() {
        var options = LineBreaking(); options.maxCharacters = 12
        let words = (0..<6).map { word("word\($0)", Double($0), Double($0) + 0.5) }
        let lines = lyricLines(from: words, breaking: options)
        XCTAssertTrue(lines.allSatisfy { $0.text.count <= 12 }, "\(lines.map(\.text))")
        XCTAssertEqual(lines.map(\.text), ["word0 word1", "word2 word3", "word4 word5"])
    }

    func testAMusicalPhraseBoundaryStartsANewLine() {
        var options = LineBreaking(); options.phrases = [0...10, 10.01...20]
        let lines = lyricLines(from: [word("one", 9, 9.5), word("two", 9.6, 9.9), word("three", 10.1, 10.5)], breaking: options)
        XCTAssertEqual(lines.map(\.text), ["one two", "three"])
    }

    func testBlankWordsAreDroppedAndTextIsTrimmed() {
        let lines = lyricLines(from: [word(" Driving", 7, 8), word("  ", 8, 8.1), word(" down ", 8.1, 8.5)])
        XCTAssertEqual(lines.map(\.text), ["Driving down"])
        XCTAssertEqual(lyricLines(from: []), [])
    }

    func testALineReportsItsLowestWordConfidence() {
        let line = lyricLines(from: [word("a", 0, 1, c: 0.9), word("b", 1, 2, c: 0.3), word("c", 2, 3)]).first!
        XCTAssertEqual(line.confidence, 0.3)
        XCTAssertNil(lyricLines(from: [word("a", 0, 1)]).first!.confidence)
    }
}

/// Dropping words that an engine made up over an instrumental passage.
final class VocalGateTests: XCTestCase {
    func testWordsOutsideTheSungStretchesAreDropped() {
        let words = [word("sung", 10, 10.5), word("invented", 30, 30.5), word("edge", 20.1, 20.4)]
        let kept = gated(words, toVocalRanges: [9...12, 15...20], tolerance: 0.3)
        XCTAssertEqual(kept.map(\.text), ["sung", "edge"], "the tolerance keeps a word just past the edge")
    }

    func testNoRangesMeansNothingIsDropped() {
        let words = [word("a", 0, 1)]
        XCTAssertEqual(gated(words, toVocalRanges: []), words)
    }

    func testEnergyDetectorFindsTheLoudStretchesOfAStem() {
        let rate = 1000.0
        var samples = [Float](repeating: 0, count: 10_000)              // 10 s
        for i in 1000..<3000 { samples[i] = 0.5 }                       // singing 1 to 3 s
        for i in 3000..<3200 { samples[i] = 0 }                         // a breath of 0.2 s
        for i in 3200..<4000 { samples[i] = 0.4 }                       // 3.2 to 4 s
        for i in 7000..<7050 { samples[i] = 0.5 }                       // a 50 ms click
        for i in 0..<10_000 where samples[i] == 0 { samples[i] = 0.001 } // faint bleed everywhere
        let ranges = vocalRanges(energyOf: samples, sampleRate: rate)
        XCTAssertEqual(ranges.count, 1, "\(ranges)")
        XCTAssertEqual(ranges[0].lowerBound, 1, accuracy: 0.06)
        XCTAssertEqual(ranges[0].upperBound, 4, accuracy: 0.06)
    }

    func testSilenceGivesNoRanges() {
        XCTAssertEqual(vocalRanges(energyOf: [Float](repeating: 0, count: 1000), sampleRate: 1000), [])
        XCTAssertEqual(vocalRanges(energyOf: [], sampleRate: 1000), [])
    }

    func testMergingJoinsCloseRangesOnly() {
        XCTAssertEqual(merged([0...1, 1.2...2, 5...6], closerThan: 0.4), [0...2, 5...6])
    }
}

/// Which line lights up for a playback position.
final class LyricSyncTests: XCTestCase {
    // Lines: "one two" 10 to 12, "three" 15 to 16, "four" 40 to 41.
    private let lines = lyricLines(from: [word("one", 10, 11), word("two", 11, 12), word("three", 15, 16), word("four", 40, 41)])

    func testBeforeTheFirstLineNothingIsLit() {
        XCTAssertNil(LyricSync.currentLineIndex(in: lines, at: 5))
        XCTAssertEqual(LyricSync.currentLineIndex(in: lines, at: 9.95), 0, "a line lights up a moment early")
    }

    func testTheLastStartedLineStaysLitThroughAGap() {
        XCTAssertEqual(LyricSync.currentLineIndex(in: lines, at: 11.5), 0)
        XCTAssertEqual(LyricSync.currentLineIndex(in: lines, at: 14), 0)
        XCTAssertEqual(LyricSync.currentLineIndex(in: lines, at: 20), 1)
        XCTAssertEqual(LyricSync.currentLineIndex(in: lines, at: 100), 2)
    }

    func testALongGapIsInstrumental() {
        XCTAssertFalse(LyricSync.isInstrumental(in: lines, at: 13.5), "the gap from 12 to 15 is too short to count")
        XCTAssertTrue(LyricSync.isInstrumental(in: lines, at: 30), "the gap from 16 to 40 counts")
        XCTAssertFalse(LyricSync.isInstrumental(in: lines, at: 15.5), "mid-line is never instrumental")
        XCTAssertTrue(LyricSync.isInstrumental(in: lines, at: 2), "a long intro counts")
        XCTAssertFalse(LyricSync.isInstrumental(in: lines, at: 8))
    }

    func testProgressCountsTheWordsSungSoFar() {
        XCTAssertEqual(LyricSync.progress(in: lines[0], at: 9), 0)
        XCTAssertEqual(LyricSync.progress(in: lines[0], at: 10.5), 0.5)
        XCTAssertEqual(LyricSync.progress(in: lines[0], at: 12), 1)
        XCTAssertEqual(LyricSync.progress(in: LyricLine(id: 9, words: []), at: 1), 0)
    }
}

/// Sheets are kept once per song file.
final class LyricSheetStoreTests: XCTestCase {
    private func sheet(_ key: String) -> LyricSheet {
        LyricSheet(songKey: key, engine: .speechAnalyzer, separated: true, language: "en",
                   lines: lyricLines(from: [word("a", 0, 1, c: 0.9)]), madeAt: Date(timeIntervalSince1970: 1_000_000))
    }

    func testASavedSheetComesBackAndCanBeDeleted() throws {
        let dir = TempDir("lyrics")
        let store = FileLyricSheetStore(directory: dir.url.appendingPathComponent("Lyrics"))
        XCTAssertNil(store.load(songKey: "k1"))
        try store.save(sheet("k1"))
        XCTAssertEqual(store.load(songKey: "k1"), sheet("k1"))
        store.delete(songKey: "k1")
        XCTAssertNil(store.load(songKey: "k1"))
        try store.save(sheet("k2")); store.deleteAll()
        XCTAssertNil(store.load(songKey: "k2"))
    }

    func testAnOlderFormatIsIgnored() throws {
        let dir = TempDir("lyrics")
        let store = FileLyricSheetStore(directory: dir.url)
        var old = sheet("k"); old.version = 0
        try store.save(old)
        XCTAssertNil(store.load(songKey: "k"), "a sheet from an older format is made again")
    }

    func testTheSongKeyFollowsTheFileNotItsFolder() throws {
        let dir = TempDir("songs")
        let a = dir.url.appendingPathComponent("song.mp3"); try Data("abc".utf8).write(to: a)
        let moved = dir.url.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: true)
        let b = moved.appendingPathComponent("song.mp3"); try FileManager.default.copyItem(at: a, to: b)
        try FileManager.default.setAttributes([.modificationDate: try FileManager.default.attributesOfItem(atPath: a.path)[.modificationDate]!], ofItemAtPath: b.path)
        XCTAssertEqual(lyricSongKey(for: a), lyricSongKey(for: b), "same name, size and date: same song")
        let other = dir.url.appendingPathComponent("other.mp3"); try Data("abc".utf8).write(to: other)
        XCTAssertNotEqual(lyricSongKey(for: a), lyricSongKey(for: other))
        XCTAssertNil(lyricSongKey(for: dir.url.appendingPathComponent("missing.mp3")))
        XCTAssertEqual(lyricSongKey(for: a)?.count, 64)
    }
}

/// The experiment's switches persist and default to off.
final class LyricsExperimentStoreTests: XCTestCase {
    func testDefaultsAreOffAppleSpeechAndSeparation() {
        let store = LyricsExperimentStore(defaults: isolatedDefaults())
        XCTAssertEqual(store.load(), LyricsExperimentSettings(enabled: false, engine: .speechAnalyzer, separateVocals: true))
        XCTAssertTrue(store.load().panelShown, "the lyrics section starts open")
    }

    /// The person can fold the lyrics section away on the card; that choice outlives the song and the launch.
    func testFoldingThePanelAwayIsRemembered() {
        let defaults = isolatedDefaults()
        let store = LyricsExperimentStore(defaults: defaults)
        var settings = store.load()
        settings.panelShown = false
        store.save(settings)
        XCTAssertFalse(LyricsExperimentStore(defaults: defaults).load().panelShown)
        defaults.set("nonsense", forKey: lyricsPanelShownKey)
        XCTAssertTrue(store.load().panelShown, "a bad value falls back to open")
    }

    func testSavedSettingsComeBackAndBadValuesFallBack() {
        let defaults = isolatedDefaults()
        let store = LyricsExperimentStore(defaults: defaults)
        store.save(LyricsExperimentSettings(enabled: true, engine: .whisperKit, separateVocals: false))
        XCTAssertEqual(store.load(), LyricsExperimentSettings(enabled: true, engine: .whisperKit, separateVocals: false))
        defaults.set("nonsense", forKey: lyricsEngineKey)
        XCTAssertEqual(store.load().engine, .speechAnalyzer)
        XCTAssertTrue(store.load().enabled, "the other values are kept")
    }
}

// MARK: - Pipeline with fakes

final class FakeLyricTranscriber: LyricTranscribing, @unchecked Sendable {
    let engine: LyricEngine
    var words: [TimedWord]
    private(set) var transcribed: [URL] = []
    private(set) var languages: [String?] = []
    init(engine: LyricEngine = .speechAnalyzer, words: [TimedWord]) { self.engine = engine; self.words = words }
    func transcribe(_ url: URL, language: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> [TimedWord] {
        transcribed.append(url); languages.append(language)
        progress(0.5); progress(1)
        return words
    }
}

final class FakeVocalSeparator: VocalSeparating, @unchecked Sendable {
    private(set) var separated: [URL] = []
    func separateVocals(from url: URL, into directory: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        separated.append(url)
        progress(1)
        let out = directory.appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-vocals.wav")
        try Data("vocals".utf8).write(to: out)
        return out
    }
}

final class FakeVocalActivity: VocalActivityDetecting, @unchecked Sendable {
    var ranges: [ClosedRange<Double>]
    private(set) var asked: [URL] = []
    init(ranges: [ClosedRange<Double>]) { self.ranges = ranges }
    func vocalRanges(in url: URL) async throws -> [ClosedRange<Double>] { asked.append(url); return ranges }
}

/// Collects what the pipeline reports, in order, stage by stage.
private final class Progress: @unchecked Sendable {
    private(set) var stages: [LyricsPipeline.Stage] = []
    private(set) var shares: [LyricsPipeline.Stage: [Double]] = [:]
    func note(_ stage: LyricsPipeline.Stage, _ share: Double) {
        if stages.last != stage { stages.append(stage) }
        shares[stage, default: []].append(share)
    }
}

final class LyricsPipelineTests: XCTestCase {
    private let song = Fixtures.url("long30.mp3")

    func testSeparatesTranscribesGatesGroupsAndSaves() async throws {
        let dir = TempDir("pipeline")
        let store = FileLyricSheetStore(directory: dir.url.appendingPathComponent("Lyrics"))
        let transcriber = FakeLyricTranscriber(words: [word("sung", 1, 1.5), word("ghost", 20, 20.5), word("more", 2, 2.5)])
        let separator = FakeVocalSeparator()
        let activity = FakeVocalActivity(ranges: [0...5])
        let pipeline = LyricsPipeline(transcriber: transcriber, separator: separator, activity: activity, store: store,
                                      workDirectory: dir.url.appendingPathComponent("work"))
        let seen = Progress()
        let sheet = try await pipeline.makeSheet(for: song, songKey: "key", language: "en") { stage, share in seen.note(stage, share) }
        XCTAssertEqual(seen.stages, [.separating, .transcribing, .finishing])
        XCTAssertEqual(seen.shares[.transcribing], [0, 0.5, 1], "the engine's own progress comes through")
        XCTAssertEqual(seen.shares[.finishing]?.last, 1)
        XCTAssertEqual(separator.separated, [song])
        XCTAssertEqual(transcriber.transcribed.first?.lastPathComponent, "long30-vocals.wav", "the transcriber hears the vocals, not the mix")
        XCTAssertEqual(activity.asked.first?.lastPathComponent, "long30-vocals.wav")
        XCTAssertEqual(sheet.lines.map(\.text), ["sung more"], "the ghost word over the instrumental is gone")
        XCTAssertTrue(sheet.separated); XCTAssertEqual(sheet.engine, .speechAnalyzer); XCTAssertEqual(sheet.language, "en")
        XCTAssertEqual(store.load(songKey: "key"), sheet)
        XCTAssertFalse(FileManager.default.fileExists(atPath: transcriber.transcribed[0].path), "the vocals file is cleaned up")
    }

    func testWithoutASeparatorTheMixIsTranscribedAndNothingIsGated() async throws {
        let dir = TempDir("pipeline")
        let store = FileLyricSheetStore(directory: dir.url)
        let transcriber = FakeLyricTranscriber(engine: .whisperKit, words: [word("a", 1, 2), word("b", 30, 31)])
        let pipeline = LyricsPipeline(transcriber: transcriber, separator: nil, activity: nil, store: store, workDirectory: dir.url)
        let sheet = try await pipeline.makeSheet(for: song, songKey: "k", language: nil)
        XCTAssertEqual(transcriber.transcribed, [song])
        XCTAssertEqual(transcriber.languages, [nil])
        XCTAssertFalse(sheet.separated); XCTAssertEqual(sheet.engine, .whisperKit)
        XCTAssertEqual(sheet.lines.map(\.text), ["a", "b"])
    }

    func testNothingTranscribedIsAnErrorAndSavesNothing() async throws {
        let dir = TempDir("pipeline")
        let store = FileLyricSheetStore(directory: dir.url)
        let pipeline = LyricsPipeline(transcriber: FakeLyricTranscriber(words: []), separator: nil, activity: nil, store: store, workDirectory: dir.url)
        do {
            _ = try await pipeline.makeSheet(for: song, songKey: "k", language: nil)
            XCTFail("expected an error")
        } catch let error as LyricsError {
            XCTAssertEqual(error, .nothingTranscribed)
        }
        XCTAssertNil(store.load(songKey: "k"))
    }
}
