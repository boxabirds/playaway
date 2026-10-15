import XCTest
@testable import PlayawayCore

/// Reproduces "dragging the play head stutters": the song kept playing, or was sought several times, while the slider
/// moved, and then sought again on release. Now it pauses for the drag and seeks once on release.
final class ScrubTests: XCTestCase {
    private func rig(playing: Bool = true) -> (TransportViewModel, AVPlaybackEngine, RecordingAudioBackend, URL) {
        let backend = RecordingAudioBackend()
        let engine = makeEngine(backend: backend)
        let url = PlaylistFixture().urls[0]
        _ = engine.play(url)
        if !playing { engine.pause() }
        let transport = TransportViewModel(engine: engine, registry: ActiveSessionRegistry(), runsTimer: false)
        return (transport, engine, backend, url)
    }

    func testTheSongPausesAtOnceWhenTheFingerGoesDownAndPlaysNothingWhileItIsDown() {
        let (transport, engine, backend, _) = rig()
        let startsBefore = backend.log.filter { $0.hasPrefix("start:") }.count
        transport.beginScrub()
        XCTAssertEqual(engine.state, .paused)
        XCTAssertTrue(backend.log.contains { $0.hasPrefix("pause:") })
        XCTAssertEqual(backend.log.filter { $0.hasPrefix("start:") }.count, startsBefore, "nothing starts while the finger is down")
    }

    func testReleaseSeeksOnceAndResumesFromThatPlace() throws {
        let (transport, engine, backend, _) = rig()
        transport.beginScrub()
        try transport.endScrub(toSeconds: 2)
        XCTAssertEqual(engine.state, .playing)
        XCTAssertEqual(engine.position, 2)
        let starts = backend.log.filter { $0.hasPrefix("start:") }
        XCTAssertEqual(starts.count, 2, "the original start and one resume, so no stretch is replayed: \(starts)")
        XCTAssertTrue(starts.last!.hasSuffix("@2.0"), "the resume starts at the place the finger lifted: \(starts)")
    }

    func testAPausedSongStaysPausedAfterAScrub() throws {
        let (transport, engine, _, _) = rig(playing: false)
        transport.beginScrub()
        try transport.endScrub(toSeconds: 3)
        XCTAssertEqual(engine.state, .paused)
        XCTAssertEqual(engine.position, 3)
    }

    func testAnImpossiblePlaceLeavesTheSongPlayingAndReportsIt() {
        let (transport, engine, _, _) = rig()
        transport.beginScrub()
        XCTAssertThrowsError(try transport.endScrub(toSeconds: 1_000_000)) { XCTAssertEqual($0 as? TransportViewModel.ActionError, .invalidSeekPosition) }
        XCTAssertEqual(engine.state, .playing, "it carries on from where it was")
    }

    func testScrubbingWithNothingLoadedDoesNothingAndEndingReportsIt() {
        let engine = makeEngine()
        let transport = TransportViewModel(engine: engine, registry: ActiveSessionRegistry(), runsTimer: false)
        transport.beginScrub()
        XCTAssertEqual(engine.state, .idle)
        XCTAssertThrowsError(try transport.endScrub(toSeconds: 5))
    }

    func testASecondBeginWithoutAnEndDoesNotLoseTheOriginalPlayingState() throws {
        let (transport, engine, _, _) = rig()
        transport.beginScrub()
        transport.beginScrub()            // a duplicate begin (for example a gesture restarting) must not mark it as paused
        try transport.endScrub(toSeconds: 4)
        XCTAssertEqual(engine.state, .playing)
    }
}

/// Reproduces "moving the slider stops the music": the finger lifting was never reported (another gesture took the touch),
/// so the song stayed paused for good.
final class ScrubWatchdogTests: XCTestCase {
    private func waitUntil(_ condition: @escaping () -> Bool, timeout: TimeInterval = 3) {
        let done = expectation(description: "condition")
        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
            if condition() { timer.invalidate(); done.fulfill() }
        }
        wait(for: [done], timeout: timeout)
        timer.invalidate()
    }

    func testAScrubWhoseLiftIsNeverReportedStillResumesPlayback() {
        let backend = RecordingAudioBackend()
        let engine = makeEngine(backend: backend)
        _ = engine.play(PlaylistFixture().urls[0])
        let transport = TransportViewModel(engine: engine, registry: ActiveSessionRegistry(), runsTimer: false)
        transport.scrubTimeout = 0.15
        transport.beginScrub()
        XCTAssertEqual(engine.state, .paused)
        waitUntil { engine.state == .playing }
        XCTAssertEqual(engine.state, .playing, "the song carries on by itself")
    }

    func testMovesKeepAScrubAliveAndTheLiftEndsItAtOnce() throws {
        let engine = makeEngine()
        _ = engine.play(PlaylistFixture().urls[0])
        let transport = TransportViewModel(engine: engine, registry: ActiveSessionRegistry(), runsTimer: false)
        transport.scrubTimeout = 0.4
        transport.beginScrub()
        for place in [0.5, 1.0, 1.5] {
            Thread.sleep(forTimeInterval: 0.25)
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            try transport.seek(toSeconds: place)
            XCTAssertEqual(engine.state, .paused, "still scrubbing while the finger moves")
        }
        try transport.endScrub(toSeconds: 1.5)
        XCTAssertEqual(engine.state, .playing)
    }
}

final class ScrubTraceTests: XCTestCase {
    func testTheSummaryReadsOffTheWholeDragInOrder() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        var trace = ScrubTrace()
        XCTAssertEqual(trace.summary, "no drag yet")
        trace.fingerDown(at: t0, wasPlaying: true)
        trace.moved(at: t0.addingTimeInterval(0.5)); trace.moved(at: t0.addingTimeInterval(1.25))
        trace.end(.lift, at: t0.addingTimeInterval(1.5))
        trace.resumeRequested(at: t0.addingTimeInterval(1.5))
        XCTAssertTrue(trace.awaitingPlayhead)
        trace.playheadSeenMoving(at: t0.addingTimeInterval(1.6))
        XCTAssertFalse(trace.awaitingPlayhead)
        XCTAssertEqual(trace.summary, "down 0 · 2 moves, last 1.25 · lift 1.50 · resume 1.50 · playhead moving 1.60")
    }

    func testALostLiftIsNamedAsTheSafetyTimer() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        var trace = ScrubTrace()
        trace.fingerDown(at: t0, wasPlaying: true)
        trace.end(.safetyTimer, at: t0.addingTimeInterval(2))
        XCTAssertTrue(trace.summary.contains("SAFETY TIMER"))
    }

    func testTheTransportRecordsADragForTheTrace() throws {
        let engine = makeEngine()
        _ = engine.play(PlaylistFixture().urls[0])
        let transport = TransportViewModel(engine: engine, registry: ActiveSessionRegistry(), runsTimer: false)
        transport.beginScrub()
        try transport.seek(toSeconds: 1); try transport.seek(toSeconds: 2)
        try transport.endScrub(toSeconds: 2)
        XCTAssertTrue(transport.scrubTrace.summary.contains("2 moves"))
        XCTAssertTrue(transport.scrubTrace.summary.contains("lift"))
        XCTAssertFalse(transport.scrubTrace.summary.contains("resume –"), "the resume was recorded")
    }
}
