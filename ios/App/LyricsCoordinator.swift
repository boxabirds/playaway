import Foundation
import Combine
import PlayawayCore
import PlayawayLyrics

/// The lyrics experiment on the iPhone: which song's sheet to show, making one on request, the models it needs, and
/// the switches. Nothing here plays sound; the engines read files. The playback position is never stored here: the
/// panel reads it live from the transport when it draws.
@MainActor
final class LyricsCoordinator: ObservableObject {
    enum Status: Equatable {
        case off                       // the experiment is switched off
        case none                      // on, but this song has no sheet yet
        case generating(stage: String, share: Double, since: Date)   // what is being done, how much of it is done, when it began
        case ready
        case failed(String)
    }

    @Published private(set) var sheet: LyricSheet?
    @Published private(set) var status: Status = .off
    @Published var settings: LyricsExperimentSettings {
        didSet { store.save(settings); showSheetForCurrentSong() }
    }
    /// Download progress per model name while a download runs.
    @Published private(set) var downloads: [String: Double] = [:]
    @Published private(set) var benchmarkReport: URL?

    nonisolated static let lowConfidence = 0.5
    static let userScrollHold: TimeInterval = 3

    private let store = LyricsExperimentStore()
    private let sheets: any LyricSheetStoring
    private let workDirectory: URL
    private var currentURL: URL?
    private var currentKey: String?
    private var job: Task<Void, Never>?

    init(sheets: any LyricSheetStoring = FileLyricSheetStore.standard()) {
        self.sheets = sheets
        settings = store.load()
        workDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("LyricsWork", isDirectory: true)
    }

    // MARK: The song under way

    func songChanged(_ url: URL?) {
        guard url != currentURL else { return }
        job?.cancel(); job = nil
        currentURL = url
        currentKey = url.flatMap(lyricSongKey(for:))
        showSheetForCurrentSong()
    }

    private func showSheetForCurrentSong() {
        guard settings.enabled else { sheet = nil; status = .off; return }
        if let key = currentKey, let found = sheets.load(songKey: key) {
            sheet = found; status = .ready
        } else {
            sheet = nil
            if case .generating = status {} else { status = currentURL == nil ? .off : .none }
        }
    }

    // MARK: Making a sheet

    var separatorInstalled: Bool { ModelDownload.mdxVocals.isInstalled }
    var whisperInstalled: Bool { WhisperKitTranscriber().isAvailable }

    /// What stops a sheet being made with the current switches, in the person's words; nil when nothing does.
    var blocker: String? {
        if settings.engine == .whisperKit, !whisperInstalled { return "Download the Whisper model in Experiments first." }
        if settings.separateVocals, !separatorInstalled { return "Download the vocal separator in Experiments first." }
        return nil
    }

    func makeLyrics() {
        guard let url = currentURL, let key = currentKey else { return }
        if let blocker { status = .failed(blocker); return }
        job?.cancel()
        let pipeline = LyricsPipeline(transcriber: transcriber(for: settings.engine),
                                      separator: settings.separateVocals ? MDXNetSeparator() : nil,
                                      activity: activityDetector(separated: settings.separateVocals),
                                      store: sheets, workDirectory: workDirectory)
        let began = Date()
        status = .generating(stage: "Starting", share: 0, since: began)
        job = Task.detached(priority: .utility) { [weak self] in
            let owner = self                    // one weak read, shared by the progress reports below
            do {
                let made = try await pipeline.makeSheet(for: url, songKey: key, language: nil) { stage, share in
                    Task { @MainActor in
                        guard let self = owner, case .generating = self.status else { return }
                        self.status = .generating(stage: Self.name(of: stage), share: share, since: began)
                    }
                }
                await MainActor.run { [weak self] in
                    guard let self, self.currentKey == key else { return }
                    self.sheet = made; self.status = .ready
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.currentKey == key else { return }
                    self.status = .failed(Self.explain(error))
                }
            }
        }
    }

    func cancel() { job?.cancel(); job = nil; showSheetForCurrentSong() }

    private static func name(of stage: LyricsPipeline.Stage) -> String {
        switch stage {
        case .separating: "Separating the vocals"
        case .transcribing: "Listening"
        case .finishing: "Finishing"
        }
    }

    private static func explain(_ error: Error) -> String {
        switch error {
        case LyricsError.nothingTranscribed: "No words were heard in this song."
        case LyricsError.unsupported(let why): why
        default: "The lyrics could not be made: \(error.localizedDescription)"
        }
    }

    private func transcriber(for engine: LyricEngine) -> any LyricTranscribing {
        switch engine {
        case .speechAnalyzer: SpeechAnalyzerTranscriber()
        case .whisperKit: WhisperKitTranscriber()
        }
    }

    private func activityDetector(separated: Bool) -> (any VocalActivityDetecting)? {
        if separated { return StemEnergyActivity() }
        #if canImport(MusicUnderstanding)
        if #available(iOS 27, *) { return MusicUnderstandingActivity() }
        #endif
        return nil
    }

    // MARK: Models and the cache

    func installSeparator() {
        let download = ModelDownload.mdxVocals
        downloads[download.name] = 0
        Task { [weak self] in
            let owner = self
            do {
                try await download.install { share in Task { @MainActor in owner?.downloads[download.name] = share } }
            } catch { }
            await MainActor.run { [weak self] in self?.downloads[download.name] = nil; self?.objectWillChange.send() }
        }
    }

    func installWhisper() {
        let name = "Whisper"
        downloads[name] = 0
        Task { [weak self] in
            try? await WhisperKitTranscriber().install()
            await MainActor.run { [weak self] in self?.downloads[name] = nil; self?.objectWillChange.send() }
        }
    }

    func clearCache() {
        sheets.deleteAll()
        showSheetForCurrentSong()
    }

    /// Every engine and source available on this phone, run on the song under way; the report goes to the app's
    /// Documents folder, where the Files app shows it.
    func benchmarkCurrentSong() {
        guard let url = currentURL else { return }
        status = .generating(stage: "Benchmarking", share: 0, since: Date())
        let separator = separatorInstalled ? MDXNetSeparator() : nil
        let engines: [(String, any LyricTranscribing)] = [("apple", SpeechAnalyzerTranscriber())] + (whisperInstalled ? [("whisper", WhisperKitTranscriber())] : [])
        let work = workDirectory
        Task.detached(priority: .utility) { [weak self] in
            var lines = ["# Lyrics benchmark: \(url.lastPathComponent)", "", "| Arm | Words | Low confidence | Over silence | Seconds |", "|---|---|---|---|---|"]
            var sources: [(String, URL, [ClosedRange<Double>])] = [("mix", url, [])]
            if let separator {
                try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let started = Date()
                if let vocals = try? await separator.separateVocals(from: url, into: work) {
                    let ranges = (try? await StemEnergyActivity().vocalRanges(in: vocals)) ?? []
                    lines.append("| separation | | | | \(String(format: "%.1f", Date().timeIntervalSince(started))) |")
                    sources.append(("vocals", vocals, ranges)); sources[0].2 = ranges
                }
            }
            for (sourceName, source, ranges) in sources {
                for (engineName, engine) in engines {
                    let started = Date()
                    do {
                        let words = try await engine.transcribe(source, language: nil)
                        let low = words.filter { ($0.confidence ?? 1) < LyricsCoordinator.lowConfidence }.count
                        let over = ranges.isEmpty ? 0 : words.count - gated(words, toVocalRanges: ranges).count
                        lines.append("| \(engineName)/\(sourceName) | \(words.count) | \(low) | \(over) | \(String(format: "%.1f", Date().timeIntervalSince(started))) |")
                    } catch {
                        lines.append("| \(engineName)/\(sourceName) | failed: \(error.localizedDescription) | | | |")
                    }
                }
            }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let report = documents.appendingPathComponent("lyrics-benchmark-\(stamp).md")
            try? lines.joined(separator: "\n").write(to: report, atomically: true, encoding: .utf8)
            await MainActor.run { [weak self] in self?.benchmarkReport = report; self?.showSheetForCurrentSong() }
        }
    }

    #if DEBUG
    /// Test aid: the experiment as a fresh install has it, off with nothing made, so one test's state cannot leak into
    /// the next launch.
    func resetForTests() {
        sheets.deleteAll()
        settings = LyricsExperimentSettings()
    }

    /// Test aid: a ready-made sheet for a song, so the panel can be tested without any model.
    func seedFakeSheet(for url: URL) {
        guard let key = lyricSongKey(for: url) else { return }
        // A word every 1.5 s with 0.3 s between words, so lines of three words start at 2 + 4.5 n seconds.
        let words = (0..<24).map { i in TimedWord("word\(i + 1)", start: 2 + Double(i) * 1.5, end: 3.2 + Double(i) * 1.5, confidence: i % 7 == 6 ? 0.3 : 0.9) }
        var options = LineBreaking(); options.maxCharacters = 20
        let sheet = LyricSheet(songKey: key, engine: .speechAnalyzer, separated: false, language: "en", lines: lyricLines(from: words, breaking: options))
        try? sheets.save(sheet)
        settings.enabled = true
    }
    #endif
}
