// Measures the lyrics engines on a folder of songs with known lyrics, on this Mac.
//
//   swift run -c release lyrics-eval <folder> [--out report.md] [--whisper base,small,large-v3-v20240930_626MB] [--no-separation]
//
// For every audio file with a sibling `<name>.txt` (the lyrics as sung, one line per line), each engine is run on the
// mix and on the separated vocals. Reported per arm: word error rate against the text, words sung over silence
// (by the stem's energy), seconds of work per minute of audio. Everything runs on this machine; nothing is uploaded.
import Foundation
import PlayawayCore
import PlayawayLyrics

// MARK: Arguments

var folder: URL?
var reportURL = URL(fileURLWithPath: "lyrics-eval-report.md")
var whisperModels = ["base"]
var separation = true
var arguments = Array(CommandLine.arguments.dropFirst())
while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "--out": reportURL = URL(fileURLWithPath: arguments.removeFirst())
    case "--whisper": whisperModels = arguments.removeFirst().split(separator: ",").map(String.init)
    case "--no-separation": separation = false
    default: folder = URL(fileURLWithPath: argument)
    }
}
guard let folder else {
    print("usage: lyrics-eval <folder with songs and <name>.txt lyrics> [--out report.md] [--whisper base,small] [--no-separation]")
    exit(2)
}

// MARK: Word error rate

func normalised(_ text: String) -> [String] {
    text.lowercased()
        .replacingOccurrences(of: "’", with: "'")
        .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
        .filter { !$0.isEmpty }
}

/// Levenshtein distance over words: substitutions, insertions and deletions, divided by the reference length.
func wordErrorRate(reference: [String], hypothesis: [String]) -> Double {
    guard !reference.isEmpty else { return hypothesis.isEmpty ? 0 : 1 }
    var previous = Array(0...hypothesis.count)
    for (i, r) in reference.enumerated() {
        var current = [i + 1] + [Int](repeating: 0, count: hypothesis.count)
        for (j, h) in hypothesis.enumerated() {
            current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (r == h ? 0 : 1))
        }
        previous = current
    }
    return Double(previous[hypothesis.count]) / Double(reference.count)
}

// MARK: Arms

struct Arm {
    let name: String
    let transcriber: any LyricTranscribing
    let separated: Bool
}

struct Measurement {
    let song: String
    let arm: String
    let wer: Double
    let words: Int
    let referenceWords: Int
    let overSilence: Int
    let secondsPerMinute: Double
    let lowConfidence: Int
    let error: String?
}

let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "flac", "aac"]
let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
let songs = files.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
    .filter { FileManager.default.fileExists(atPath: $0.deletingPathExtension().appendingPathExtension("txt").path) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
guard !songs.isEmpty else { print("no audio file with a sibling .txt in \(folder.path)"); exit(1) }

var transcribers: [(String, any LyricTranscribing)] = []
if #available(macOS 26, *) { transcribers.append(("apple", SpeechAnalyzerTranscriber(locale: Locale(identifier: "en-US")))) }
for model in whisperModels { transcribers.append(("whisper-\(model)", WhisperKitTranscriber(modelName: model))) }

let separator = MDXNetSeparator()
if separation, !separator.isAvailable {
    print("downloading the separator model (\(ModelDownload.mdxVocals.bytes / 1_000_000) MB)…")
    try await ModelDownload.mdxVocals.install()
}
let work = FileManager.default.temporaryDirectory.appendingPathComponent("lyrics-eval-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

var measurements: [Measurement] = []
let lowConfidenceBar = 0.5
for song in songs {
    let name = song.deletingPathExtension().lastPathComponent
    let reference = normalised((try? String(contentsOf: song.deletingPathExtension().appendingPathExtension("txt"), encoding: .utf8)) ?? "")
    let seconds = (try? AudioSamples.read(song).left.count).map { Double($0) / AudioSamples.separatorRate } ?? 0
    print("== \(name): \(reference.count) reference words, \(Int(seconds)) s")

    var sources: [(String, URL, [ClosedRange<Double>])] = [("mix", song, [])]
    if separation {
        let started = Date()
        do {
            let vocals = try await separator.separateVocals(from: song, into: work)
            let ranges = try await StemEnergyActivity().vocalRanges(in: vocals)
            print(String(format: "   separated in %.1f s; %d sung stretches", Date().timeIntervalSince(started), ranges.count))
            sources.append(("vocals", vocals, ranges))
            sources[0].2 = ranges                       // the stem's silence applies to the mix too
        } catch {
            print("   separation failed: \(error)")
        }
    }

    for (sourceName, url, ranges) in sources {
        for (engineName, transcriber) in transcribers {
            let armName = "\(engineName)/\(sourceName)"
            let started = Date()
            do {
                let words = try await transcriber.transcribe(url, language: "en-US")
                let spent = Date().timeIntervalSince(started)
                let hypothesis = normalised(words.map(\.text).joined(separator: " "))
                let wer = wordErrorRate(reference: reference, hypothesis: hypothesis)
                let overSilence = ranges.isEmpty ? 0 : words.count - gated(words, toVocalRanges: ranges).count
                let low = words.filter { ($0.confidence ?? 1) < lowConfidenceBar }.count
                measurements.append(Measurement(song: name, arm: armName, wer: wer, words: words.count, referenceWords: reference.count,
                                                overSilence: overSilence, secondsPerMinute: seconds > 0 ? spent / (seconds / 60) : 0,
                                                lowConfidence: low, error: nil))
                print(String(format: "   %-22@ WER %5.1f%%  words %4d  over silence %3d  low-confidence %3d  %5.1f s/min",
                             armName as NSString, wer * 100, words.count, overSilence, low, spent / max(seconds / 60, 0.01)))
                let transcript = words.map { String(format: "%7.2f-%7.2f %@", $0.start, $0.end, $0.text) }.joined(separator: "\n")
                try? transcript.write(to: reportURL.deletingLastPathComponent().appendingPathComponent("\(name).\(armName.replacingOccurrences(of: "/", with: "-")).txt"),
                                      atomically: true, encoding: .utf8)
            } catch {
                print("   \(armName) failed: \(error)")
                measurements.append(Measurement(song: name, arm: armName, wer: 1, words: 0, referenceWords: reference.count,
                                                overSilence: 0, secondsPerMinute: 0, lowConfidence: 0, error: "\(error)"))
            }
        }
    }
}

// MARK: Report

var report = "# Lyrics engine evaluation\n\nRun \(Date()) on this Mac. WER = word error rate against the supplied lyrics (lower is better). "
report += "\"Over silence\" = words placed where the separated vocal stem is silent (likely invented). "
report += "\"Low confidence\" = words the engine itself rated under \(lowConfidenceBar).\n\n"
let arms = Array(Set(measurements.map(\.arm))).sorted()
report += "## Per arm, averaged over \(songs.count) songs\n\n| Arm | Mean WER | Over silence | Low confidence | s per minute of audio | Failures |\n|---|---|---|---|---|---|\n"
for arm in arms {
    let rows = measurements.filter { $0.arm == arm }
    let ok = rows.filter { $0.error == nil }
    let meanWER = ok.isEmpty ? 1 : ok.map(\.wer).reduce(0, +) / Double(ok.count)
    report += String(format: "| %@ | %.1f%% | %d | %d | %.1f | %d |\n", arm, meanWER * 100, ok.map(\.overSilence).reduce(0, +),
                     ok.map(\.lowConfidence).reduce(0, +), ok.isEmpty ? 0 : ok.map(\.secondsPerMinute).reduce(0, +) / Double(ok.count), rows.count - ok.count)
}
report += "\n## Per song\n\n| Song | Arm | WER | Words (ref) | Over silence | Low confidence | s/min |\n|---|---|---|---|---|---|---|\n"
for m in measurements {
    report += String(format: "| %@ | %@ | %@ | %d (%d) | %d | %d | %.1f |\n", m.song, m.arm, m.error == nil ? String(format: "%.1f%%", m.wer * 100) : "failed: \(m.error!)",
                     m.words, m.referenceWords, m.overSilence, m.lowConfidence, m.secondsPerMinute)
}
report += "\nNot measured here: word timing accuracy (no timed reference), language detection, the phone.\n"
try report.write(to: reportURL, atomically: true, encoding: .utf8)
print("report: \(reportURL.path)")
