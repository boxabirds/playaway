import XCTest
import Combine
@testable import LocalPlayer

final class PlaybackEngineTests: XCTestCase {
    let mp3 = Fixtures.url("track1.mp3")
    let wav = Fixtures.url("tone.wav")
    let m4a = Fixtures.url("tone.m4a")

    // MARK: play (story 1)

    func testPlayStartsFromZeroAndReportsPlaying() {
        let backend = RecordingAudioBackend()
        let engine = makeEngine(backend: backend)
        XCTAssertEqual(engine.play(mp3), .playing)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(engine.position, 0)
        XCTAssertEqual(engine.currentURL, mp3)
    }

    func testSecondPlayReplacesFirst() {            // TC-34
        let backend = RecordingAudioBackend()
        let engine = makeEngine(backend: backend)
        for new in [wav, m4a] {
            _ = engine.play(mp3)
            XCTAssertEqual(engine.play(new), .playing)
            XCTAssertEqual(engine.currentURL, new)
            XCTAssertEqual(backend.playing?.url, new, "only the new file is running")
            XCTAssertEqual(backend.players.filter(\.running).count, 1)
        }
        XCTAssertTrue(backend.log.contains("stop:track1.mp3"))
    }

    func testNoOutputDeviceStartsNothing() {         // TC-35 / TC-51
        let backend = RecordingAudioBackend()
        let engine = makeEngine(backend: backend, hasDevice: false)
        XCTAssertEqual(engine.play(mp3), .noOutputDevice)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertTrue(backend.players.isEmpty, "no audio output call is made")
    }

    func testFileFinishingReturnsToIdle() {          // TC-36
        let backend = RecordingAudioBackend()
        let engine = makeEngine(backend: backend)
        var finished: [URL] = []
        let sub = engine.events.sink { if case .finished(let url) = $0 { finished.append(url) } }
        _ = engine.play(mp3)
        backend.latest?.finish()
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(finished, [mp3])
        sub.cancel()
    }

    func testUnstartableFileReturnsFailedAndKeepsPreviousPlayback() {   // TC-37
        let backend = RecordingAudioBackend()
        backend.unreadableNames = ["tone.wav"]
        let engine = makeEngine(backend: backend)
        _ = engine.play(mp3)
        guard case .failed = engine.play(wav) else { return XCTFail("expected failed") }
        XCTAssertEqual(engine.currentURL, mp3)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(backend.playing?.url, mp3)
    }

    func testStartFailureReturnsFailedAndLeavesStateAsBefore() {
        let backend = RecordingAudioBackend()
        let engine = makeEngine(backend: backend)
        backend.failStart = true
        guard case .failed = engine.play(mp3) else { return XCTFail("expected failed") }
        XCTAssertEqual(engine.state, .idle)
    }

    func testStalePlayerFinishDoesNotAffectNewFile() {
        let backend = RecordingAudioBackend()
        let engine = makeEngine(backend: backend)
        _ = engine.play(mp3)
        let first = backend.latest!
        _ = engine.play(wav)
        first.finish()
        XCTAssertTrue(engine.isPlaying, "a replaced player's late finish is ignored")
        XCTAssertEqual(engine.currentURL, wav)
    }

    func testRealAVAudioPlayerPlaysAndStopsAllThreeFormats() throws {
        guard SystemOutputDevices().hasOutputDevice else { throw XCTSkip("no output device on this machine") }
        let engine = AVPlaybackEngine(settings: InMemoryVolumeStore(volume: 0, muted: true))   // silent
        for url in [mp3, wav, m4a] {
            XCTAssertEqual(engine.play(url), .playing, url.lastPathComponent)
            XCTAssertTrue(engine.duration > 0)
            engine.stop()
            XCTAssertEqual(engine.state, .idle)
        }
    }

    func testRealEngineFailsOnDamagedFile() throws {
        let dir = TempDir()
        let damaged = makeUnreadableMP3(in: dir)
        let empty = dir.path("empty.mp3"); FileManager.default.createFile(atPath: empty.path, contents: Data())
        let engine = AVPlaybackEngine(settings: InMemoryVolumeStore(volume: 0, muted: true))
        guard SystemOutputDevices().hasOutputDevice else { throw XCTSkip("no output device") }
        for url in [damaged, empty] {
            guard case .failed = engine.play(url) else { return XCTFail("expected failed for \(url.lastPathComponent)") }
            XCTAssertEqual(engine.state, .idle)
        }
    }

    // MARK: transport matrix (TC-01..TC-12)

    private func engineIn(_ state: TransportState) -> (AVPlaybackEngine, RecordingAudioBackend) {
        let backend = RecordingAudioBackend()
        let engine = makeEngine(backend: backend)
        switch state {
        case .idle: break
        case .playing: _ = engine.play(mp3)
        case .paused: _ = engine.play(mp3); _ = engine.seek(toSeconds: 1.5); engine.pause()
        }
        return (engine, backend)
    }

    func testTransportMatrix() {
        enum Action: CaseIterable { case pause, resume, stop, seek }
        // expected (state after, position after) per starting state and action
        for start in [TransportState.idle, .playing, .paused] {
            for action in Action.allCases {
                let (engine, _) = engineIn(start)
                let positionBefore = engine.position
                var seekResult: Bool?
                switch action {
                case .pause: engine.pause()
                case .resume: engine.resume()
                case .stop: engine.stop()
                case .seek: seekResult = engine.seek(toSeconds: 2)
                }
                let label = "\(start) + \(action)"
                switch (start, action) {
                case (.idle, _):
                    XCTAssertEqual(engine.state, .idle, label)
                    XCTAssertEqual(engine.position, 0, label)
                    if action == .seek { XCTAssertEqual(seekResult, false, label) }
                case (.playing, .pause):
                    XCTAssertEqual(engine.state, .paused, label)
                    XCTAssertEqual(engine.position, positionBefore, label)    // TC-05 / TC-80
                case (.playing, .resume):
                    XCTAssertEqual(engine.state, .playing, label)
                case (.playing, .stop), (.paused, .stop):
                    XCTAssertEqual(engine.state, .idle, label)
                    XCTAssertEqual(engine.position, 0, label)
                case (.playing, .seek):
                    XCTAssertEqual(seekResult, true, label)
                    XCTAssertEqual(engine.state, .playing, label)
                    XCTAssertEqual(engine.position, 2, label)
                case (.paused, .pause):
                    XCTAssertEqual(engine.state, .paused, label)
                    XCTAssertEqual(engine.position, positionBefore, label)
                case (.paused, .resume):
                    XCTAssertEqual(engine.state, .playing, label)
                    XCTAssertEqual(engine.position, positionBefore, "resume continues, not from 0 (TC-81)")
                case (.paused, .seek):
                    XCTAssertEqual(seekResult, true, label)
                    XCTAssertEqual(engine.state, .paused, label)
                    XCTAssertEqual(engine.position, 2, label)
                }
            }
        }
    }

    func testPauseResumeKeepsPositionAtSinkLevel() {   // TC-13
        let (engine, backend) = engineIn(.idle)
        _ = engine.play(mp3)
        backend.latest!.currentTime = 2.25
        engine.pause()
        engine.resume()
        XCTAssertTrue(backend.log.contains("pause:track1.mp3@2.25"))
        XCTAssertTrue(backend.log.contains("start:track1.mp3@2.25"), "audio resumes from the paused frame")
    }

    func testStopThenPlayNewFileStartsAtZero() {       // TC-14
        let (engine, backend) = engineIn(.playing)
        engine.stop()
        _ = engine.play(wav)
        XCTAssertEqual(engine.position, 0)
        XCTAssertTrue(backend.log.last!.hasPrefix("start:tone.wav@0"))
    }

    // MARK: seek boundaries (TC-40..TC-46)

    func testSeekBoundaries() {
        let (engine, _) = engineIn(.playing)           // duration 4
        XCTAssertTrue(engine.seek(toSeconds: 0)); XCTAssertEqual(engine.position, 0)
        XCTAssertTrue(engine.seek(toSeconds: 4)); XCTAssertEqual(engine.position, 4)
        for bad in [4.001, -1, .nan, .infinity] {
            let before = engine.position
            XCTAssertFalse(engine.seek(toSeconds: bad), "\(bad)")
            XCTAssertEqual(engine.position, before, "refused seek leaves position")
            XCTAssertTrue(engine.isPlaying, "and playback state")
        }
    }

    func testSeekWhilePausedStaysPausedAndSilent() {       // TC-46
        let (engine, backend) = engineIn(.paused)
        let startsBefore = backend.startedNames.count
        XCTAssertTrue(engine.seek(toSeconds: 3))
        XCTAssertEqual(engine.state, .paused)
        XCTAssertEqual(backend.startedNames.count, startsBefore, "no audio started")
    }

    // MARK: volume and mute (TC-50..TC-64)

    func testVolumeAppliesImmediatelyAndClamps() {
        let store = InMemoryVolumeStore()
        let (engine, backend) = (makeEngine(store: store), RecordingAudioBackend())
        _ = backend
        engine.volume = 0.0; XCTAssertEqual(engine.volume, 0.0)
        engine.volume = 1.0; XCTAssertEqual(engine.volume, 1.0)
        engine.volume = -0.1; XCTAssertEqual(engine.volume, 0.0, "TC-53")
        engine.volume = 1.1; XCTAssertEqual(engine.volume, 1.0, "TC-54")
        engine.volume = 0.5
        engine.volume = .nan; XCTAssertEqual(engine.volume, 0.5, "TC-55: refused")
        XCTAssertEqual(store.volume, 0.5)
        engine.volume = 2.0
        XCTAssertEqual(store.volume, 1.0, "TC-123: the saved value is the clamped one")
    }

    func testVolumeReachesTheSinkWithoutInterruptingTheTrack() {   // TC-52 / TC-56
        let backend = RecordingAudioBackend()
        let engine = makeEngine(backend: backend)
        _ = engine.play(mp3)
        backend.latest!.currentTime = 1.0
        engine.volume = 0.5
        XCTAssertEqual(backend.latest!.gain, 0.5)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(engine.position, 1.0)
    }

    func testMuteSilencesWithoutChangingVolume() {      // TC-60 / TC-61 / TC-83
        let backend = RecordingAudioBackend()
        let engine = makeEngine(backend: backend)
        _ = engine.play(mp3)
        engine.volume = 0.7
        engine.setMuted(true)
        XCTAssertEqual(backend.latest!.gain, 0)
        XCTAssertEqual(engine.volume, 0.7)
        XCTAssertTrue(engine.isMuted)
        engine.setMuted(false)
        XCTAssertEqual(backend.latest!.gain, 0.7, accuracy: 0.0001)
        XCTAssertFalse(engine.isMuted)
    }

    func testChangingVolumeWhileMutedStaysSilent() {    // TC-62 (provisional)
        let backend = RecordingAudioBackend()
        let engine = makeEngine(backend: backend)
        _ = engine.play(mp3)
        engine.setMuted(true)
        engine.volume = 0.3
        XCTAssertEqual(engine.volume, 0.3)
        XCTAssertTrue(engine.isMuted)
        XCTAssertEqual(backend.latest!.gain, 0)
    }

    func testMuteWhileIdleAndNewFileStaysSilent() {     // TC-63 / TC-64
        let backend = RecordingAudioBackend()
        let engine = makeEngine(backend: backend)
        engine.setMuted(true)
        XCTAssertTrue(engine.isMuted)
        _ = engine.play(mp3)
        XCTAssertEqual(backend.latest!.gain, 0)
        _ = engine.play(wav)
        XCTAssertEqual(backend.latest!.gain, 0, "mute persists across tracks")
    }

    func testVolumeNeverTouchesTheSystemVolume() throws {   // TC-84: static check of the sources
        let sources = Fixtures.directory.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/LocalPlayer")
        let forbidden = ["kAudioDevicePropertyVolumeScalar", "kAudioHardwareServiceDeviceProperty_VirtualMainVolume",
                         "set volume output volume", "kAudioDevicePropertyMute"]
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for token in forbidden { XCTAssertFalse(text.contains(token), "\(url.lastPathComponent) uses \(token)") }
        }
    }

    // MARK: persistence (TC-100..TC-123)

    func testPersistedVolumeAndMuteMatrix() {
        enum Stored { case none, value(Any) }
        let volumes: [(String, Any?, Double)] = [("V1", nil, 1.0), ("V2", 0.4, 0.4), ("V3", 1.5, 1.0), ("V4", "loud", 1.0)]
        let mutes: [(String, Any?, Bool)] = [("M1", nil, false), ("M2", true, true), ("M3", false, false), ("M4", "yes", false)]
        for (vName, vStored, vExpected) in volumes {
            for (mName, mStored, mExpected) in mutes {
                let defaults = isolatedDefaults()
                if let vStored { defaults.set(vStored, forKey: volumeSettingKey) }
                if let mStored { defaults.set(mStored, forKey: muteSettingKey) }
                let engine = AVPlaybackEngine(backend: RecordingAudioBackend(), devices: StubOutputDevices(hasOutputDevice: true),
                                              settings: VolumeSettingsStore(defaults: defaults))
                XCTAssertEqual(engine.volume, vExpected, "\(vName) \(mName)")
                XCTAssertEqual(engine.isMuted, mExpected, "\(vName) \(mName)")
            }
        }
    }

    func testPersistedBoundaries() {
        for (stored, expected) in [(0.0, 0.0), (1.0, 1.0), (-0.001, 1.0), (Double.nan, 1.0)] {
            let defaults = isolatedDefaults()
            defaults.set(stored, forKey: volumeSettingKey)
            XCTAssertEqual(VolumeSettingsStore(defaults: defaults).load().volume, expected, "stored \(stored)")
        }
    }

    func testVolumeAndMuteSurviveRelaunchIndependently() {   // TC-120 / TC-121
        let defaults = isolatedDefaults()
        let first = AVPlaybackEngine(backend: RecordingAudioBackend(), devices: StubOutputDevices(hasOutputDevice: true),
                                     settings: VolumeSettingsStore(defaults: defaults))
        first.setMuted(true)
        first.volume = 0.3
        let second = AVPlaybackEngine(backend: RecordingAudioBackend(), devices: StubOutputDevices(hasOutputDevice: true),
                                      settings: VolumeSettingsStore(defaults: defaults))
        XCTAssertEqual(second.volume, 0.3)
        XCTAssertTrue(second.isMuted)
    }

    func testOnlyVolumeAndMuteKeysAreWritten() {          // TC-89
        let defaults = isolatedDefaults()
        let engine = AVPlaybackEngine(backend: RecordingAudioBackend(), devices: StubOutputDevices(hasOutputDevice: true),
                                      settings: VolumeSettingsStore(defaults: defaults))
        engine.volume = 0.2; engine.setMuted(true)
        let keys = Set(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("player") })
        XCTAssertEqual(keys, [volumeSettingKey, muteSettingKey])
    }

    func testInitialLevelsAreAppliedBeforeAnyViewExists() {   // TC-122
        let store = InMemoryVolumeStore(volume: 0.4, muted: true)
        let engine = makeEngine(store: store)
        XCTAssertEqual(engine.volume, 0.4)
        XCTAssertTrue(engine.isMuted)
    }

    func testEngineDoesNotTouchAudioBeforeFirstPlay() {       // TC-53 of story 6
        let backend = RecordingAudioBackend()
        _ = makeEngine(backend: backend)
        XCTAssertTrue(backend.players.isEmpty)
        XCTAssertTrue(backend.log.isEmpty)
    }
}
