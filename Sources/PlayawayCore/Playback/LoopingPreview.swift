import Foundation
import AVFoundation

/// The short snippet that loops while a finger holds still on the position slider. It is a separate sound from the song, so
/// that the loop can be made seamless; the song itself stays paused where it was until the finger lifts.
package protocol LoopingPreviewing: AnyObject {
    var isPlaying: Bool { get }
    /// Starts looping `length` seconds of `url` from `seconds`. False when it cannot (the file cannot be read).
    func start(url: URL, at seconds: Double, length: Double) -> Bool
    /// Fades the loop out and stops it. Returns the place in the song the loop had reached, or nil when it was not playing.
    @discardableResult func stop() -> Double?
}

/// The loop, played by AVAudioEngine. The snippet is read once into a buffer and its end is blended into its start
/// (`seamlessLoop`), so playing the buffer round and round has no click at the loop point. Nothing here runs in a render
/// callback: AVFoundation's own thread plays the buffer.
package final class AVLoopingPreview: LoopingPreviewing {
    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var songStart = 0.0
    private var loopFrames = 0
    private var sampleRate = 44_100.0
    package private(set) var isPlaying = false

    /// How long the loop takes to fade out when it stops, so that stopping cannot click either.
    private static let stopFade: TimeInterval = 0.01
    private static let stopFadeSteps = 5

    package init() {}

    package func start(url: URL, at seconds: Double, length: Double) -> Bool {
        stop()
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        let format = file.processingFormat
        let rate = format.sampleRate
        let startFrame = AVAudioFramePosition(max(seconds, 0) * rate)
        guard startFrame < file.length else { return false }
        let wantedLoop = Int(length * rate)
        let available = Int(file.length - startFrame)
        let readFrames = min(wantedLoop + loopCrossfadeFrames, available)
        guard readFrames > 0,
              let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(readFrames)) else { return false }
        file.framePosition = startFrame
        guard (try? file.read(into: source, frameCount: AVAudioFrameCount(readFrames))) != nil, source.frameLength > 0,
              let channels = source.floatChannelData else { return false }
        let frames = Int(source.frameLength)
        let loopLength = min(wantedLoop, frames)
        guard let loop = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(loopLength)),
              let out = loop.floatChannelData else { return false }
        for channel in 0..<Int(format.channelCount) {
            let samples = Array(UnsafeBufferPointer(start: channels[channel], count: frames))
            let blended = seamlessLoop(samples, loopFrames: loopLength, fadeFrames: min(loopCrossfadeFrames, frames - loopLength))
            for index in 0..<loopLength { out[channel][index] = blended[index] }
        }
        loop.frameLength = AVAudioFrameCount(loopLength)

        let newEngine = AVAudioEngine()
        let newNode = AVAudioPlayerNode()
        newEngine.attach(newNode)
        newEngine.connect(newNode, to: newEngine.mainMixerNode, format: format)
        guard (try? newEngine.start()) != nil else { return false }
        newNode.scheduleBuffer(loop, at: nil, options: .loops, completionHandler: nil)
        newNode.play()
        engine = newEngine; node = newNode
        songStart = Double(startFrame) / rate
        loopFrames = loopLength
        sampleRate = rate
        isPlaying = true
        return true
    }

    @discardableResult
    package func stop() -> Double? {
        guard isPlaying, let engine, let node else { return nil }
        var place = songStart
        if let nodeTime = node.lastRenderTime, let playerTime = node.playerTime(forNodeTime: nodeTime), loopFrames > 0 {
            place += Double(playerTime.sampleTime % AVAudioFramePosition(loopFrames)) / sampleRate
        }
        let mixer = engine.mainMixerNode
        for step in 1...Self.stopFadeSteps {
            mixer.outputVolume = 1 - Float(step) / Float(Self.stopFadeSteps)
            Thread.sleep(forTimeInterval: Self.stopFade / Double(Self.stopFadeSteps))
        }
        node.stop()
        engine.stop()
        self.engine = nil; self.node = nil
        isPlaying = false
        return place
    }
}
