import Foundation
import WhisperKit
import PlayawayCore

/// OpenAI Whisper on Core ML through Argmax's WhisperKit. The model is fetched once into the app's Models folder.
package final class WhisperKitTranscriber: LyricTranscribing, @unchecked Sendable {
    package let engine = LyricEngine.whisperKit
    /// The variant Argmax recommends for accuracy on both iPhone and Mac; about 626 MB.
    package static let defaultModel = "large-v3-v20240930_626MB"
    package static let smallModel = "small"

    package let modelName: String
    private let downloadBase: URL
    private var kit: WhisperKit?

    package init(modelName: String = WhisperKitTranscriber.defaultModel, downloadBase: URL = ModelDownload.modelsDirectory()) {
        self.modelName = modelName
        self.downloadBase = downloadBase
    }

    /// True once the model files are on disk, so transcribing will not start a download.
    package var isAvailable: Bool {
        let folder = downloadBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return false }
        return names.contains { $0.hasSuffix(modelName) }
    }

    /// Fetches the model if it is missing.
    package func install() async throws { _ = try await loaded() }

    private func loaded() async throws -> WhisperKit {
        if let kit { return kit }
        let kit = try await WhisperKit(WhisperKitConfig(model: modelName, downloadBase: downloadBase, verbose: false, logLevel: .error))
        self.kit = kit
        return kit
    }

    /// How often the share done is read off WhisperKit while it works.
    private static let progressPoll: Duration = .milliseconds(500)

    package func transcribe(_ url: URL, language: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> [TimedWord] {
        let kit = try await loaded()
        var options = DecodingOptions()
        options.wordTimestamps = true
        options.language = language.map { String($0.prefix(2)) }
        let kitProgress = kit.progress
        let poll = Task {
            while !Task.isCancelled {
                progress(kitProgress.fractionCompleted)
                try? await Task.sleep(for: Self.progressPoll)
            }
        }
        defer { poll.cancel() }
        let results = try await kit.transcribe(audioPath: url.path, decodeOptions: options)
        progress(1)
        var words: [TimedWord] = []
        for segment in results.flatMap(\.segments) {
            for word in segment.words ?? [] where !word.word.hasPrefix("[") {           // "[Pause]" and the like are not lyrics
                words.append(TimedWord(word.word, start: Double(word.start), end: Double(word.end), confidence: Double(word.probability)))
            }
        }
        return words
    }
}
