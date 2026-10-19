import Foundation
import AVFoundation

/// A whole song decoded once into memory (16-bit, one array per channel), so that the scrub loop can cut a snippet from any
/// place at once and exactly. Seeking inside an MP3 with `AVAudioFile` decodes everything before the place, so the further
/// along the song, the longer the loop took to start, and an approximate seek made the snippets differ in length and place
/// (owner's list, on the iPad: "strange delays, strange durations, the further along the song the weirder").
package final class DecodedSong: @unchecked Sendable {
    /// Songs longer than this are not decoded whole (10 minutes is about 106 MB at 44.1 kHz stereo).
    package static let maximumSeconds: Double = 600
    private static let chunkFrames: AVAudioFrameCount = 1 << 16
    private static let int16Scale: Float = 32768

    package let url: URL
    package let sampleRate: Double
    package let channels: [[Int16]]
    package var frameCount: Int { channels.first?.count ?? 0 }

    package init(url: URL, sampleRate: Double, channels: [[Int16]]) {
        self.url = url; self.sampleRate = sampleRate; self.channels = channels
    }

    /// Reads the whole file. Nil when it cannot be read or is longer than `maximumSeconds`. `stillWanted` is asked between
    /// chunks, so a decode for a song that has been replaced stops early.
    package static func decode(_ url: URL, stillWanted: () -> Bool = { true }) -> DecodedSong? {
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: false) else { return nil }
        let format = file.processingFormat
        let rate = format.sampleRate
        guard rate > 0, Double(file.length) / rate <= maximumSeconds,
              let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { return nil }
        let channelCount = Int(format.channelCount)
        var out = [[Int16]](repeating: [], count: channelCount)
        for index in 0..<channelCount { out[index].reserveCapacity(Int(file.length)) }
        while file.framePosition < file.length {
            guard stillWanted() else { return nil }
            guard (try? file.read(into: chunk, frameCount: chunkFrames)) != nil, chunk.frameLength > 0,
                  let data = chunk.int16ChannelData else { break }
            for index in 0..<channelCount { out[index].append(contentsOf: UnsafeBufferPointer(start: data[index], count: Int(chunk.frameLength))) }
        }
        guard out.first?.isEmpty == false else { return nil }
        return DecodedSong(url: url, sampleRate: rate, channels: out)
    }

    /// The snippet that starts at `startFrame` as one seamless loop per channel, `loopFrames` long (shorter near the end of
    /// the song). Nil when the place is past the end.
    package func loop(startFrame: Int, loopFrames wanted: Int, fadeFrames: Int) -> [[Float]]? {
        guard startFrame >= 0, startFrame < frameCount, wanted > 0 else { return nil }
        let available = frameCount - startFrame
        let read = min(wanted + fadeFrames, available)
        let loopLength = min(wanted, read)
        return channels.map { samples in
            let slice = (0..<read).map { Float(samples[startFrame + $0]) / Self.int16Scale }
            return seamlessLoop(slice, loopFrames: loopLength, fadeFrames: min(fadeFrames, read - loopLength))
        }
    }
}
