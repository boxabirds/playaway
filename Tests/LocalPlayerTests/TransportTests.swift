import XCTest
import AppKit
@testable import LocalPlayer

@MainActor
final class TransportViewModelTests: XCTestCase {
    var app: TestApp!
    var vm: TransportViewModel { app.services.transport }
    override func setUp() async throws { app = TestApp() }
    override func tearDown() async throws { app.tearDown() }

    func play(_ name: String = "track1.mp3") { _ = app.services.engine.play(Fixtures.url(name)) }

    func testShowsRealStateIncludingPauseFromOutside() {                                  // TC-70/71/74
        play()
        XCTAssertTrue(vm.isPlaying)
        XCTAssertEqual(vm.nowPlaying, "track1.mp3")
        app.services.engine.pause()                                                         // e.g. a script
        XCTAssertFalse(vm.isPlaying, "Play shows when paused by any means")
        XCTAssertTrue(vm.trackControlsAvailable)
    }

    func testIdleDisablesTrackControlsButNotVolumeAndMute() {                              // TC-72
        XCTAssertFalse(vm.trackControlsAvailable)
        XCTAssertFalse(vm.skipControlsAvailable)
        XCTAssertThrowsError(try vm.pause())
        XCTAssertThrowsError(try vm.stop())
        XCTAssertThrowsError(try vm.seek(toSeconds: 1))
        XCTAssertThrowsError(try vm.next())
        XCTAssertThrowsError(try vm.previous())
        XCTAssertNoThrow(try vm.setVolume(0.5))
        vm.setMuted(true)
        XCTAssertTrue(vm.isMuted)
    }

    func testPauseResumeStopSeek() {
        play()
        try? vm.seek(toSeconds: 2)
        XCTAssertEqual(vm.position, 2)
        XCTAssertNoThrow(try vm.pause())
        vm.playPause()
        XCTAssertTrue(vm.isPlaying)
        XCTAssertThrowsError(try vm.seek(toSeconds: 99)) { XCTAssertEqual($0 as? TransportViewModel.ActionError, .invalidSeekPosition) }
        XCTAssertNoThrow(try vm.stop())
        XCTAssertEqual(vm.position, 0)
        XCTAssertEqual(vm.state, .idle)
    }

    func testNextAndPreviousDoNothingForASingleFile() {                                    // TC-20/21/85
        play()
        let log = app.backend.log
        XCTAssertNoThrow(try vm.next())
        XCTAssertNoThrow(try vm.previous())
        XCTAssertEqual(app.backend.log, log)
        XCTAssertFalse(vm.skipControlsAvailable)
    }

    func testVolumeRangesAndScriptMapping() {
        XCTAssertNoThrow(try vm.setScriptVolume(50))
        XCTAssertEqual(vm.volume, 0.5)
        XCTAssertNoThrow(try vm.setScriptVolume(0)); XCTAssertEqual(vm.volume, 0)
        XCTAssertNoThrow(try vm.setScriptVolume(100)); XCTAssertEqual(vm.volume, 1)
        for bad in [-1, 101] {
            XCTAssertThrowsError(try vm.setScriptVolume(bad))
            XCTAssertEqual(vm.volume, 1, "refused: volume unchanged")
        }
        XCTAssertThrowsError(try vm.setVolume(.nan))
    }

    func testMuteKeepsVolumeAndTogglesBack() {
        try? vm.setVolume(0.5)
        vm.toggleMute()
        XCTAssertTrue(vm.isMuted); XCTAssertEqual(vm.volume, 0.5)
        vm.toggleMute()
        XCTAssertFalse(vm.isMuted); XCTAssertEqual(vm.volume, 0.5)
    }

    func testFirstPublishedStateHoldsRestoredLevels() {                                    // TC-75
        let defaults = isolatedDefaults()
        VolumeSettingsStore(defaults: defaults).saveVolume(0.4)
        VolumeSettingsStore(defaults: defaults).saveMuted(true)
        let engine = AVPlaybackEngine(backend: RecordingAudioBackend(), devices: StubOutputDevices(hasOutputDevice: true),
                                      settings: VolumeSettingsStore(defaults: defaults))
        let model = TransportViewModel(engine: engine, registry: ActiveSessionRegistry(), runsTimer: false)
        XCTAssertEqual(model.volume, 0.4)
        XCTAssertTrue(model.isMuted)
    }

    func testPlayWhenIdleStartsTheFrontPlaylistOrReplaysLastFile() {
        XCTAssertThrowsError(try vm.play(), "nothing to play")
        app.services.openCoordinator.open(Fixtures.url("tone.wav"))
        app.services.engine.stop()
        XCTAssertNoThrow(try vm.play())
        XCTAssertEqual(app.services.engine.currentURL, Fixtures.url("tone.wav"))
        app.services.engine.stop()
        let doc = app.newDocument()
        doc.addFiles([Fixtures.url("track2.mp3")])
        XCTAssertNoThrow(try vm.play())
        XCTAssertEqual(app.services.engine.currentURL?.lastPathComponent, "track2.mp3")
    }

    func testFormatTime() {
        XCTAssertEqual(TransportViewModel.formatTime(0), "0:00")
        XCTAssertEqual(TransportViewModel.formatTime(65.9), "1:05")
        XCTAssertEqual(TransportViewModel.formatTime(-3), "0:00")
        XCTAssertEqual(TransportViewModel.formatTime(.nan), "0:00")
    }
}

@MainActor
final class ControlsViewTests: XCTestCase {
    var app: TestApp!
    override func setUp() async throws { app = TestApp() }
    override func tearDown() async throws { app.tearDown() }

    func testTransportViewFollowsStateAndActionsReachTheEngine() {                           // TC-70..74, E2E-1 level
        let view = TransportControlsView(viewModel: app.services.transport)
        XCTAssertEqual(view.nowPlayingLabel.stringValue, TransportControlsView.nothingPlayingText)
        XCTAssertFalse(view.stopButton.isEnabled)
        XCTAssertTrue(view.volumeSlider.isEnabled)
        XCTAssertTrue(view.muteButton.isEnabled)
        _ = app.services.engine.play(Fixtures.url("track1.mp3"))
        spin { view.nowPlayingLabel.stringValue == "track1.mp3" }
        XCTAssertEqual(view.playPauseButton.accessibilityLabel(), "Pause")
        XCTAssertTrue(view.stopButton.isEnabled)
        view.playPausePressed()
        spin { view.playPauseButton.accessibilityLabel() == "Play" }
        XCTAssertEqual(app.services.engine.state, .paused)
        view.positionSlider.doubleValue = 3
        view.positionChanged()
        XCTAssertEqual(app.services.engine.position, 3)
        view.volumeSlider.doubleValue = 0.25
        view.volumeChanged()
        XCTAssertEqual(app.services.engine.volume, 0.25)
        view.mutePressed()
        spin { view.muteButton.state == .on }
        XCTAssertEqual(view.muteButton.accessibilityValue() as? String, "on")
        XCTAssertEqual(view.volumeSlider.doubleValue, 0.25, accuracy: 0.001, "still shows the chosen level while muted")
        view.stopPressed()
        spin { view.elapsedLabel.stringValue == "0:00" && !view.stopButton.isEnabled }
        XCTAssertEqual(app.services.engine.state, .idle)
    }

    func testModeControlsShowAndStepStateAndAreShared() {                                     // TC-30..37, TC-104, E2E-4
        let a = PlayModeControls(settings: app.services.settings)
        let b = PlayModeControls(settings: app.services.settings)
        XCTAssertEqual(a.repeatButton.title, "Repeat: Off")
        var seen: [String] = []
        for _ in 0..<3 { a.repeatPressed(); seen.append(a.repeatButton.title) }
        XCTAssertEqual(seen, ["Repeat: All", "Repeat: One", "Repeat: Off"])
        a.shufflePressed()
        spin { b.shuffleButton.state == .on }
        XCTAssertEqual(b.shuffleButton.state, .on, "window B shows the same state")
        XCTAssertEqual(b.repeatButton.title, "Repeat: Off", "independent controls")
        XCTAssertEqual(a.shuffleButton.accessibilityValue() as? String, "on")
    }

    func testTransportAndModeStateDoNotInterruptPlayback() {                                   // TC-38
        _ = app.services.engine.play(Fixtures.url("track1.mp3"))
        let log = app.backend.log
        let modes = PlayModeControls(settings: app.services.settings)
        modes.shufflePressed(); modes.repeatPressed()
        XCTAssertEqual(app.backend.log, log, "the track keeps playing without restarting")
    }
}
