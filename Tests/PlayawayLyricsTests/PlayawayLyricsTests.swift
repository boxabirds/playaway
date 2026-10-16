import XCTest
import PlayawayCore
@testable import PlayawayLyrics

private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures")

/// The STFT must match the one the model was trained with; a wrong scale or frame count fails silently in sound.
final class ShortTimeFourierTests: XCTestCase {
    private let stft = ShortTimeFourier(n: MDXNetSeparator.nFFT, hop: MDXNetSeparator.hop, bins: MDXNetSeparator.dimF)

    func testAChunkGivesExactly256Frames() {
        XCTAssertEqual(stft.frames(for: MDXNetSeparator.chunkSamples), 256)
        XCTAssertEqual(stft.transform([Float](repeating: 0, count: MDXNetSeparator.chunkSamples)).re.count, 256)
    }

    func testTheForwardScaleIsThePlainDFT() {
        // A unit sine on bin k through a periodic Hann window has magnitude N/4 at bin k.
        let k = 100, n = MDXNetSeparator.nFFT
        let sine = (0..<MDXNetSeparator.chunkSamples).map { sin(2 * Float.pi * Float(k) * Float($0) / Float(n)) }
        let s = stft.transform(sine)
        XCTAssertEqual(hypot(s.re[10][k], s.im[10][k]), Float(n) / 4, accuracy: 1)
        XCTAssertEqual(hypot(s.re[10][k + 7], s.im[10][k + 7]), 0, accuracy: 1, "nothing far from the sine's bin")
    }

    func testTheInverseUndoesTheForward() {
        var generator = SystemRandomNumberGenerator()
        let noise = (0..<MDXNetSeparator.chunkSamples).map { _ in Float.random(in: -0.5...0.5, using: &generator) }
        let s = stft.transform(noise)
        let back = stft.inverseTransform(re: s.re, im: s.im, length: noise.count)
        var errorPower: Float = 0, power: Float = 0
        for i in 0..<noise.count { errorPower += (noise[i] - back[i]) * (noise[i] - back[i]); power += noise[i] * noise[i] }
        let snr = 10 * log10(power / max(errorPower, 1e-20))
        XCTAssertGreaterThan(snr, 35, "round trip SNR \(snr) dB")
    }
}

/// The separator itself, only when the model has been downloaded on this machine.
final class MDXNetSeparatorTests: XCTestCase {
    func testASongIsSeparatedIntoAQuieterVocalsFile() async throws {
        let separator = MDXNetSeparator()
        try XCTSkipUnless(separator.isAvailable, "download the MDX model first (ModelDownload.mdxVocals)")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lyrics-sep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = try await separator.separateVocals(from: fixtures.appendingPathComponent("long30.mp3"), into: dir)
        let mix = try AudioSamples.read(fixtures.appendingPathComponent("long30.mp3"))
        let vocals = try AudioSamples.read(out)
        XCTAssertEqual(vocals.left.count, mix.left.count, accuracy: 2048)
        func rms(_ x: [Float]) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot() }
        XCTAssertLessThan(rms(vocals.left), rms(mix.left), "the vocals stem carries less than the whole mix")
    }
}

/// Apple's transcriber on the real 30 s fixture: it may transcribe nothing (the fixture is not a song), but it must
/// run to the end and every word it gives must be timed inside the file.
@available(macOS 26, *)
final class SpeechAnalyzerTranscriberTests: XCTestCase {
    func testRunsOverAFileAndTimesItsWordsInsideIt() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PLAYAWAY_LYRICS_ENGINES"] == "1", "set PLAYAWAY_LYRICS_ENGINES=1")
        let words = try await SpeechAnalyzerTranscriber(locale: Locale(identifier: "en-US"))
            .transcribe(fixtures.appendingPathComponent("long30.mp3"), language: nil)
        for word in words {
            XCTAssertGreaterThanOrEqual(word.start, 0); XCTAssertLessThanOrEqual(word.end, 31); XCTAssertLessThanOrEqual(word.start, word.end)
            XCTAssertFalse(word.text.isEmpty)
        }
    }
}

final class WhisperKitTranscriberTests: XCTestCase {
    func testRunsOverAFileAndTimesItsWordsInsideIt() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PLAYAWAY_LYRICS_ENGINES"] == "1", "set PLAYAWAY_LYRICS_ENGINES=1")
        let words = try await WhisperKitTranscriber(modelName: "base").transcribe(fixtures.appendingPathComponent("long30.mp3"), language: "en")
        for word in words {
            XCTAssertGreaterThanOrEqual(word.start, 0); XCTAssertLessThanOrEqual(word.end, 31); XCTAssertLessThanOrEqual(word.start, word.end)
        }
    }
}
