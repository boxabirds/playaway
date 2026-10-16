import XCTest
@testable import PlayawayCore

/// Only one sound at a time, ever. The song and the scrub loop are two sound producers; the engine holds one lease on
/// audio, and whatever takes it silences the holder first. These reproduce the report "the scrub loop played on its own
/// while another song played": each presses something that starts the song while the loop is looping.
final class AudioExclusivityTests: XCTestCase {
    private struct Rig {
        let transport: TransportViewModel
        let preview: FakeLoopingPreview
        let engine: AVPlaybackEngine
        let backend: RecordingAudioBackend
        let playlist: PlayerRig
    }

    private static let holdDelay = 0.1
    private static let loopPlace = 1.0

    /// A playlist playing its first song, the finger holding still on the slider, the loop sounding.
    private func rigWithTheLoopSounding() throws -> Rig {
        let playlist = PlayerRig()
        let preview = playlist.backend.preview
        let transport = TransportViewModel(engine: playlist.engine, registry: playlist.registry, runsTimer: false)
        transport.activePlayerProvider = { playlist.player }
        transport.scrubHoldDelay = Self.holdDelay
        playlist.player.start()
        transport.beginScrub()
        try transport.seek(toSeconds: Self.loopPlace)
        RunLoop.main.run(until: Date().addingTimeInterval(Self.holdDelay * 2))
        XCTAssertTrue(preview.isPlaying, "the loop is sounding")
        XCTAssertEqual(playlist.engine.state, .paused, "the song is silent under it")
        return Rig(transport: transport, preview: preview, engine: playlist.engine, backend: playlist.backend, playlist: playlist)
    }

    func testNextWhileTheLoopSoundsLeavesOnlyTheNewSongSounding() throws {
        let rig = try rigWithTheLoopSounding()
        try rig.transport.next()
        XCTAssertFalse(rig.preview.isPlaying, "the loop fell silent when the next song took the audio")
        XCTAssertEqual(rig.engine.state, .playing)
        XCTAssertEqual(rig.engine.currentURL, rig.playlist.fixture.urls[1])
        XCTAssertEqual(rig.backend.ledger.overlaps, [])
        try rig.transport.endScrub(toSeconds: Self.loopPlace)
        XCTAssertEqual(rig.engine.position, 0, accuracy: 0.001, "the lift does not drag the new song to the old loop's place")
        XCTAssertEqual(rig.engine.state, .playing)
    }

    func testPlayWhileTheLoopSoundsLeavesOnlyTheSongSounding() throws {
        let rig = try rigWithTheLoopSounding()
        try rig.transport.play()                        // the card's play button, the lock screen, a headphone tap
        XCTAssertFalse(rig.preview.isPlaying, "the loop fell silent when the song took the audio")
        XCTAssertEqual(rig.engine.state, .playing)
        XCTAssertEqual(rig.backend.ledger.overlaps, [])
        try rig.transport.endScrub(toSeconds: Self.loopPlace)
        XCTAssertEqual(rig.engine.state, .playing)
        XCTAssertEqual(rig.backend.ledger.overlaps, [])
    }

    func testStoppingTheEngineWhileTheLoopSoundsSilencesTheLoop() throws {
        let rig = try rigWithTheLoopSounding()
        rig.engine.stop()                               // the playlist was deleted, or ran out of songs
        XCTAssertFalse(rig.preview.isPlaying, "no loop may outlive the song it belongs to")
        XCTAssertEqual(rig.engine.state, .idle)
    }

    func testASecondSongSilencesTheFirstBeforeItStarts() {
        let backend = RecordingAudioBackend()
        let engine = makeEngine(backend: backend)
        let fixture = PlaylistFixture()
        _ = engine.play(fixture.urls[0])
        _ = engine.play(fixture.urls[1])
        XCTAssertEqual(backend.ledger.overlaps, [], "the first song is silent before the second makes a sound")
    }

    // MARK: The engine's own guarantees, one entry point each

    private func engineWithTheLoopSounding() -> (AVPlaybackEngine, RecordingAudioBackend, PlaylistFixture) {
        let backend = RecordingAudioBackend()
        let engine = makeEngine(backend: backend)
        let fixture = PlaylistFixture()
        _ = engine.play(fixture.urls[0])
        XCTAssertTrue(engine.startPreviewLoop(at: Self.loopPlace, length: 1))
        XCTAssertTrue(engine.isPreviewing)
        XCTAssertEqual(engine.state, .paused, "starting the loop silences the song")
        XCTAssertNil(backend.playing, "no song player is running under the loop")
        return (engine, backend, fixture)
    }

    func testStartingTheLoopSilencesTheSongAndStoppingItReportsThePlace() {
        let (engine, backend, _) = engineWithTheLoopSounding()
        backend.preview.placeWhenStopped = 1.5
        XCTAssertEqual(engine.stopPreviewLoop() ?? -1, 1.5, accuracy: 0.001)
        XCTAssertFalse(engine.isPreviewing)
        XCTAssertEqual(engine.state, .paused, "stopping the loop does not start the song by itself")
        XCTAssertNil(engine.stopPreviewLoop(), "nothing to stop twice")
    }

    func testPlayingAnotherSongSilencesTheLoop() {
        let (engine, backend, fixture) = engineWithTheLoopSounding()
        XCTAssertEqual(engine.play(fixture.urls[1]), .playing)
        XCTAssertFalse(engine.isPreviewing)
        XCTAssertFalse(backend.preview.isPlaying)
        XCTAssertEqual(backend.ledger.overlaps, [])
    }

    func testResumingSilencesTheLoop() {
        let (engine, backend, _) = engineWithTheLoopSounding()
        engine.resume()
        XCTAssertEqual(engine.state, .playing)
        XCTAssertFalse(backend.preview.isPlaying)
        XCTAssertEqual(backend.ledger.overlaps, [])
    }

    func testResumingWithAFadeSilencesTheLoop() {
        let (engine, backend, _) = engineWithTheLoopSounding()
        engine.resume(fadingIn: 0.02)
        XCTAssertEqual(engine.state, .playing)
        XCTAssertFalse(backend.preview.isPlaying)
        XCTAssertEqual(backend.ledger.overlaps, [])
    }

    func testPreparingASongSilencesTheLoop() {
        let (engine, backend, fixture) = engineWithTheLoopSounding()
        XCTAssertEqual(engine.prepare(fixture.urls[1], at: 2), .ready)
        XCTAssertFalse(backend.preview.isPlaying)
        XCTAssertEqual(engine.state, .paused)
        XCTAssertEqual(backend.ledger.sounding, [], "a prepared song is silent and the loop is gone")
    }

    func testStoppingSilencesTheLoop() {
        let (engine, backend, _) = engineWithTheLoopSounding()
        engine.stop()
        XCTAssertFalse(backend.preview.isPlaying)
        XCTAssertEqual(backend.ledger.sounding, [])
    }

    func testALoopCannotStartWithNothingLoadedOrWhenTheFileCannotBeRead() {
        let backend = RecordingAudioBackend()
        let engine = makeEngine(backend: backend)
        XCTAssertFalse(engine.startPreviewLoop(at: 0, length: 1))
        _ = engine.play(PlaylistFixture().urls[0])
        backend.preview.canStart = false
        XCTAssertFalse(engine.startPreviewLoop(at: 0, length: 1))
        XCTAssertFalse(engine.isPreviewing)
        XCTAssertEqual(engine.state, .paused, "the song was silenced for the loop and stays paused: the caller decides")
    }
}

/// The lease itself: the one object that decides which sound may be heard.
final class AudioLeaseTests: XCTestCase {
    func testTakingTheLeaseSilencesTheHolderBeforeTheNewHolderIsRecorded() {
        let lease = AudioLease()
        var log: [String] = []
        lease.take(.song) { log.append("song silenced") }
        XCTAssertEqual(lease.holder, .song)
        lease.take(.preview) { log.append("preview silenced") }
        XCTAssertEqual(log, ["song silenced"])
        XCTAssertEqual(lease.holder, .preview)
        lease.take(.song) { log.append("song silenced again") }
        XCTAssertEqual(log, ["song silenced", "preview silenced"])
    }

    func testReleasingOnlyWorksForTheHolderAndSilencesNothing() {
        let lease = AudioLease()
        var silenced = 0
        lease.take(.song) { silenced += 1 }
        lease.release(.preview)
        XCTAssertEqual(lease.holder, .song, "another holder cannot release the lease")
        lease.release(.song)
        XCTAssertNil(lease.holder)
        XCTAssertEqual(silenced, 0, "a holder that fell silent by itself is not silenced again")
        lease.vacate()
        XCTAssertEqual(silenced, 0)
    }

    func testVacatingSilencesTheHolderAndFreesTheLease() {
        let lease = AudioLease()
        var silenced = 0
        lease.take(.preview) { silenced += 1 }
        lease.vacate()
        XCTAssertEqual(silenced, 1)
        XCTAssertNil(lease.holder)
    }
}

/// A source-level guard: nothing outside the engine's own files may make or own a sound producer. If this fails, a new
/// way of making a sound has appeared that the lease does not govern.
final class AudioExclusivitySourceTests: XCTestCase {
    private static let soundMakers = ["AVAudioPlayer(", "AVAudioEngine(", "AVAudioPlayerNode(", "AVPlayer(", "AVQueuePlayer(",
                                      "LoopingPreviewing", "AVLoopingPreview(", "AudioLease("]
    /// The engine and the two producers it owns. `PlaybackEngine.swift` is the protocol and names none of them.
    private static let engineFiles: Set<String> = ["AVPlaybackEngine.swift", "AudioBackend.swift", "LoopingPreview.swift", "AudioLease.swift"]

    func testOnlyTheEngineMakesSounds() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var offences: [String] = []
        for folder in ["Sources", "ios/App"] {
            let files = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" && !Self.engineFiles.contains($0.lastPathComponent) } ?? []
            XCTAssertFalse(files.isEmpty, "found sources under \(folder)")
            for file in files {
                let text = try String(contentsOf: file, encoding: .utf8)
                for maker in Self.soundMakers where text.contains(maker) { offences.append("\(file.lastPathComponent) uses \(maker)") }
            }
        }
        XCTAssertEqual(offences, [], "every sound is made inside the engine, under its lease")
    }
}
