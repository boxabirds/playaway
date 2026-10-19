import Foundation
import AVFoundation

/// The short snippet that loops while a finger holds still on the position slider. It is a separate sound from the song, so
/// that the loop can be made seamless; the song itself stays paused where it was until the finger lifts.
package protocol LoopingPreviewing: AnyObject {
    var isPlaying: Bool { get }
    /// Gets a loop ready in the background (reads the snippet, starts the audio engine) so that `start` for the same place
    /// is instant. A newer call replaces an older one that has not finished. Nothing is heard.
    func prepare(url: URL, at seconds: Double, length: Double)
    /// Starts looping `length` seconds of `url` from `seconds`. False when it cannot (the file cannot be read).
    func start(url: URL, at seconds: Double, length: Double) -> Bool
    /// The scrub is over: lets go of the audio engine that `prepare` and `start` kept running.
    func endSession()
    /// Fades the loop out and stops it. Returns the place in the song the loop had reached, or nil when it was not playing.
    @discardableResult func stop() -> Double?
}

extension LoopingPreviewing {
    package func prepare(url: URL, at seconds: Double, length: Double) {}
    package func endSession() {}
}

/// The loop, played by AVAudioEngine. The snippet is read once into a buffer and its end is blended into its start
/// (`seamlessLoop`), so playing the buffer round and round has no click at the loop point. Nothing here runs in a render
/// callback: AVFoundation's own thread plays the buffer.
///
/// Starting an audio engine and decoding a snippet of an MP3 take a noticeable time (about 0.7 s the first time and 0.1 to
/// 0.2 s after, measured on a Mac; slower on a phone), and used to happen on the main thread at the moment the finger held
/// still. Now `prepare` does both on a queue of its own as the finger moves, the engine stays running for the whole scrub,
/// and `start` for a prepared place only schedules the buffer.
package final class AVLoopingPreview: LoopingPreviewing, @unchecked Sendable {
    /// How close, in seconds, the prepared place must be to the asked-for one to be used as it is.
    private static let matchTolerance = 0.05
    /// How long the loop takes to fade out when it stops, so that stopping cannot click either.
    private static let stopFade: TimeInterval = 0.01
    private static let stopFadeSteps = 5

    /// A snippet read and an engine ready to play it.
    private struct Prepared {
        let url: URL
        let place: Double
        let length: Double
        let buffer: AVAudioPCMBuffer
        let loopFrames: Int
        let sampleRate: Double
    }

    private let queue = DispatchQueue(label: "software.away.play.loop", qos: .userInteractive)
    /// Guards `playing` and `generation`, which are read on the main thread while the queue works.
    private let lock = NSLock()
    private var playing = false
    /// Bumped by anything that makes work in flight pointless, so the work gives up at its next checkpoint.
    private var generation = 0
    /// The song decoded whole (see `DecodedSong`) and the one being decoded now, guarded by `lock`.
    private var decodedSong: DecodedSong?
    private var decodingURL: URL?
    private let decodeQueue = DispatchQueue(label: "software.away.play.loop-decode", qos: .utility)

    // Everything below is touched only on `queue`.
    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var engineFormat: AVAudioFormat?
    private var prepared: Prepared?
    private var current: Prepared?

    package init() {}

    package var isPlaying: Bool { lock.lock(); defer { lock.unlock() }; return playing }

    private func setPlaying(_ value: Bool) { lock.lock(); playing = value; lock.unlock() }
    @discardableResult private func bumpGeneration() -> Int { lock.lock(); defer { lock.unlock() }; generation += 1; return generation }
    private func isCurrent(_ gen: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return generation == gen }

    /// Starts decoding `url` whole in the background unless it already is, or is, decoded; a different song replaces it.
    private func ensureDecoding(_ url: URL) {
        lock.lock()
        if decodedSong?.url != url { decodedSong = nil }
        let needed = decodedSong == nil && decodingURL != url
        if needed { decodingURL = url }
        lock.unlock()
        guard needed else { return }
        decodeQueue.async { [self] in
            let song = DecodedSong.decode(url) { self.isDecodingTarget(url) }
            lock.lock()
            if decodingURL == url { decodingURL = nil; decodedSong = song }
            lock.unlock()
        }
    }

    private func isDecodingTarget(_ url: URL) -> Bool { lock.lock(); defer { lock.unlock() }; return decodingURL == url }
    private func decoded(for url: URL) -> DecodedSong? { lock.lock(); defer { lock.unlock() }; return decodedSong?.url == url ? decodedSong : nil }

    package func prepare(url: URL, at seconds: Double, length: Double) {
        ensureDecoding(url)
        let gen = bumpGeneration()
        queue.async { [self] in
            guard isCurrent(gen) else { return }
            guard let made = makePrepared(url: url, at: seconds, length: length, stillWanted: { self.isCurrent(gen) }) else { return }
            guard isCurrent(gen) else { return }
            prepared = made
        }
    }

    package func start(url: URL, at seconds: Double, length: Double) -> Bool {
        ensureDecoding(url)
        bumpGeneration()                                   // an older prepare for another place is not worth finishing
        var started = false
        queue.sync { started = startOnQueue(url: url, at: seconds, length: length) }
        return started
    }

    @discardableResult
    package func stop() -> Double? {
        guard isPlaying else { return nil }
        setPlaying(false)
        var place: Double?
        queue.sync { place = stopOnQueue() }
        return place
    }

    package func endSession() {
        bumpGeneration()
        queue.async { [self] in
            node?.stop(); engine?.stop()
            node = nil; engine = nil; engineFormat = nil; prepared = nil
        }
    }

    // MARK: On the queue

    /// Reads the snippet and makes sure an engine in its format is running. Nil when the file cannot be read.
    private func makePrepared(url: URL, at seconds: Double, length: Double, stillWanted: () -> Bool) -> Prepared? {
        if let prepared, prepared.url == url, prepared.length == length, abs(prepared.place - max(seconds, 0)) < Self.matchTolerance {
            return prepared
        }
        let format: AVAudioFormat, rate: Double, startFrame: AVAudioFramePosition, loopLength: Int, loop: AVAudioPCMBuffer
        if let song = decoded(for: url) {
            // From memory: exact and at once, wherever in the song.
            rate = song.sampleRate
            startFrame = AVAudioFramePosition(max(seconds, 0) * rate)
            guard let cut = song.loop(startFrame: Int(startFrame), loopFrames: Int(length * rate), fadeFrames: loopCrossfadeFrames),
                  let made = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(song.channels.count)),
                  let first = cut.first, !first.isEmpty,
                  let buffer = AVAudioPCMBuffer(pcmFormat: made, frameCapacity: AVAudioFrameCount(first.count)),
                  let out = buffer.floatChannelData else { return nil }
            format = made; loopLength = first.count; loop = buffer
            for (channel, samples) in cut.enumerated() { for index in 0..<loopLength { out[channel][index] = samples[index] } }
            loop.frameLength = AVAudioFrameCount(loopLength)
        } else {
            // Until the song has been decoded: read it from the file (slow far into an MP3, and approximate).
            guard let file = try? AVAudioFile(forReading: url) else { return nil }
            format = file.processingFormat
            rate = format.sampleRate
            startFrame = AVAudioFramePosition(max(seconds, 0) * rate)
            guard startFrame < file.length else { return nil }
            let wantedLoop = Int(length * rate)
            let available = Int(file.length - startFrame)
            let readFrames = min(wantedLoop + loopCrossfadeFrames, available)
            guard readFrames > 0,
                  let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(readFrames)) else { return nil }
            file.framePosition = startFrame
            guard (try? file.read(into: source, frameCount: AVAudioFrameCount(readFrames))) != nil, source.frameLength > 0,
                  let channels = source.floatChannelData else { return nil }
            guard stillWanted() else { return nil }
            let frames = Int(source.frameLength)
            loopLength = min(wantedLoop, frames)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(loopLength)),
                  let out = buffer.floatChannelData else { return nil }
            for channel in 0..<Int(format.channelCount) {
                let samples = Array(UnsafeBufferPointer(start: channels[channel], count: frames))
                let blended = seamlessLoop(samples, loopFrames: loopLength, fadeFrames: min(loopCrossfadeFrames, frames - loopLength))
                for index in 0..<loopLength { out[channel][index] = blended[index] }
            }
            buffer.frameLength = AVAudioFrameCount(loopLength)
            loop = buffer
        }
        guard ensureEngine(format: format) else { return nil }
        return Prepared(url: url, place: Double(startFrame) / rate, length: length, buffer: loop, loopFrames: loopLength, sampleRate: rate)
    }

    /// An engine running with one player node connected in `format`; kept from one snippet to the next while the format
    /// stays the same.
    private func ensureEngine(format: AVAudioFormat) -> Bool {
        if let engine, engine.isRunning, engineFormat == format { return true }
        node?.stop(); engine?.stop()
        let newEngine = AVAudioEngine()
        let newNode = AVAudioPlayerNode()
        newEngine.attach(newNode)
        newEngine.connect(newNode, to: newEngine.mainMixerNode, format: format)
        guard (try? newEngine.start()) != nil else { engine = nil; node = nil; engineFormat = nil; return false }
        engine = newEngine; node = newNode; engineFormat = format
        return true
    }

    private func startOnQueue(url: URL, at seconds: Double, length: Double) -> Bool {
        if isPlaying { _ = stopOnQueue() }
        guard let ready = makePrepared(url: url, at: seconds, length: length, stillWanted: { true }),
              let engine, let node else { return false }
        prepared = ready
        engine.mainMixerNode.outputVolume = 1
        node.stop()
        node.scheduleBuffer(ready.buffer, at: nil, options: .loops, completionHandler: nil)
        node.play()
        current = ready
        setPlaying(true)
        return true
    }

    /// Reports where the loop had got to and lets it fade out. The engine stays running for the next snippet.
    private func stopOnQueue() -> Double? {
        guard let current, let engine, let node else { setPlaying(false); return nil }
        var place = current.place
        if let nodeTime = node.lastRenderTime, let playerTime = node.playerTime(forNodeTime: nodeTime), current.loopFrames > 0 {
            place += Double(playerTime.sampleTime % AVAudioFramePosition(current.loopFrames)) / current.sampleRate
        }
        self.current = nil
        setPlaying(false)
        queue.async {                                       // behind this call, ahead of any next start: nothing overlaps
            let mixer = engine.mainMixerNode
            for step in 1...Self.stopFadeSteps {
                mixer.outputVolume = 1 - Float(step) / Float(Self.stopFadeSteps)
                Thread.sleep(forTimeInterval: Self.stopFade / Double(Self.stopFadeSteps))
            }
            node.stop()
            mixer.outputVolume = 1
        }
        return place
    }
}
