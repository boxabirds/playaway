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
