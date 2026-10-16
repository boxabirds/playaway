import Foundation
import PlayawayCore

/// Vocal activity from the loudness of a separated vocal stem. On a full mix it finds the music, not the voice, so
/// the pipeline only uses it when the separator ran.
package struct StemEnergyActivity: VocalActivityDetecting {
    package var settings = EnergyGateSettings.default

    package init() {}

    package func vocalRanges(in url: URL) async throws -> [ClosedRange<Double>] {
        let audio = try AudioSamples.read(url)
        return PlayawayCore.vocalRanges(energyOf: audio.mono, sampleRate: audio.rate, settings: settings)
    }
}

#if canImport(MusicUnderstanding)
import MusicUnderstanding
import AVFoundation

/// Apple's own analysis of where the singing is, on iOS 27 and macOS 27. Also knows the song's phrases.
@available(iOS 27, macOS 27, *)
package struct MusicUnderstandingActivity: VocalActivityDetecting {
    package init() {}

    package func vocalRanges(in url: URL) async throws -> [ClosedRange<Double>] {
        let session = try await MusicUnderstandingSession(asset: AVURLAsset(url: url))
        let result = try await session.analyze(for: [.instrumentActivity])
        let ranges = result.instrumentActivity?.ranges[.vocal] ?? []
        return ranges.map { CMTimeGetSeconds($0.start)...CMTimeGetSeconds($0.end) }
    }

    /// The musical phrases, for line breaking.
    package func phrases(in url: URL) async throws -> [ClosedRange<Double>] {
        let session = try await MusicUnderstandingSession(asset: AVURLAsset(url: url))
        let result = try await session.analyze(for: [.structure])
        return (result.structure?.phrases ?? []).map { CMTimeGetSeconds($0.start)...CMTimeGetSeconds($0.end) }
    }
}
#endif
