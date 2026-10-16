import Foundation
import AVFoundation
import PlayawayCore

/// Reads a song into float samples at a fixed rate, for the separator and the energy gate. Reads only; never plays.
package enum AudioSamples {
    package static let separatorRate = 44_100.0

    package struct Stereo {
        package var left: [Float]
        package var right: [Float]
        package var rate: Double
        package var mono: [Float] { zip(left, right).map { ($0 + $1) / 2 } }
    }

    package static func read(_ url: URL, rate: Double = separatorRate) throws -> Stereo {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format) else {
            throw LyricsError.unsupported("The file's audio format cannot be converted.")
        }
        let frames = AVAudioFrameCount(Double(file.length) * rate / file.processingFormat.sampleRate) + 4096
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw LyricsError.unsupported("The file is too long to read into memory.")
        }
        var error: NSError?
        var done = false
        converter.convert(to: out, error: &error) { count, status in
            if done { status.pointee = .endOfStream; return nil }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else {
                status.pointee = .endOfStream; return nil
            }
            try? file.read(into: buffer)
            if buffer.frameLength == 0 { done = true; status.pointee = .endOfStream; return nil }
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        let n = Int(out.frameLength)
        return Stereo(left: Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: n)),
                      right: Array(UnsafeBufferPointer(start: out.floatChannelData![1], count: n)), rate: rate)
    }

    /// 16-bit stereo wav, the plainest file every engine reads.
    static func writeWav(_ stereo: Stereo, to url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: stereo.rate, channels: 2, interleaved: false)!
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: stereo.rate, AVNumberOfChannelsKey: 2,
                                       AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let count = stereo.left.count
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
            throw LyricsError.unsupported("The separated audio is too long to write.")
        }
        buffer.frameLength = AVAudioFrameCount(count)
        for i in 0..<count { buffer.floatChannelData![0][i] = stereo.left[i]; buffer.floatChannelData![1][i] = stereo.right[i] }
        try file.write(from: buffer)
        file.close()
    }
}
