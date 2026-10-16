import Foundation
import AVFoundation
import CoreMedia
import Speech
import PlayawayCore

/// Apple's on-device speech model (iOS 26, macOS 26) run over a whole file. Each run of the attributed result carries
/// the time it was sung and the model's confidence; runs are words in practice, and a run of several words is split
/// evenly across its time.
@available(iOS 26, macOS 26, *)
package final class SpeechAnalyzerTranscriber: LyricTranscribing {
    package let engine = LyricEngine.speechAnalyzer
    private let locale: Locale

    package init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Locales the system model can transcribe.
    package static func supportedLanguages() async -> [String] {
        await SpeechTranscriber.supportedLocales.map(\.identifier)
    }

    package func transcribe(_ url: URL, language: String?) async throws -> [TimedWord] {
        let locale = language.map(Locale.init(identifier:)) ?? self.locale
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange, .transcriptionConfidence])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let file = try AVAudioFile(forReading: url)
        let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber], finishAfterFile: true)
        var words: [TimedWord] = []
        for try await result in transcriber.results {
            let text = result.text
            for run in text.runs {
                let piece = String(text[run.range].characters)
                let parts = piece.split(whereSeparator: \.isWhitespace).map(String.init)
                guard !parts.isEmpty else { continue }
                let range = run.audioTimeRange
                let start = range.map { CMTimeGetSeconds($0.start) } ?? CMTimeGetSeconds(result.range.start)
                let end = range.map { CMTimeGetSeconds(CMTimeRangeGetEnd($0)) } ?? CMTimeGetSeconds(CMTimeRangeGetEnd(result.range))
                let confidence = run.transcriptionConfidence.map { Double($0) }
                let step = (end - start) / Double(parts.count)
                for (i, part) in parts.enumerated() {
                    words.append(TimedWord(part, start: start + step * Double(i), end: start + step * Double(i + 1), confidence: confidence))
                }
            }
        }
        _ = analyzer
        return words
    }
}
