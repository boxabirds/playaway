import XCTest
@testable import PlayawayCore

/// Playback state lives in the engine and nowhere else. These tests fail if a screen could ever be shown anything other
/// than what the engine is doing: no stored copy, a new song always starts at the beginning, a paused load is shown like
/// any other paused song.
@MainActor
final class PlaybackStateTests: XCTestCase {
    private func rig() -> (TransportViewModel, AVPlaybackEngine, PlaylistFixture) {
        let engine = makeEngine()
        let transport = TransportViewModel(engine: engine, registry: ActiveSessionRegistry(), runsTimer: false)
        return (transport, engine, PlaylistFixture())
    }

    func testTheTransportHoldsNoCopyOfAnyPlaybackState() {
        let (transport, _, _) = rig()
        let labels = Mirror(reflecting: transport).children.compactMap(\.label)
        for forbidden in ["position", "state", "duration", "volume", "isMuted", "nowPlaying", "hasPlaylistSession", "trackPosition"] {
            XCTAssertFalse(labels.contains(forbidden) || labels.contains("_" + forbidden),
                           "TransportViewModel must not store \(forbidden): it is read live from the engine")
        }
    }

    func testEverythingTheTransportReportsIsWhatTheEngineHoldsAtThatMoment() throws {
        let (transport, engine, fixture) = rig()
        func assertSame(_ step: String) {
            XCTAssertEqual(transport.position, engine.position, step)
            XCTAssertEqual(transport.duration, engine.duration, step)
            XCTAssertEqual(transport.state, engine.state, step)
            XCTAssertEqual(transport.nowPlaying, engine.currentURL?.lastPathComponent ?? "", step)
        }
        assertSame("idle")
        _ = engine.play(fixture.urls[0]); assertSame("playing")
        try transport.seek(toSeconds: 2); assertSame("after a seek")
        engine.pause(); assertSame("paused")
        _ = engine.play(fixture.urls[1]); assertSame("after another song")
        transport.beginScrub(); assertSame("scrubbing")
        try transport.endScrub(toSeconds: 3); assertSame("after a scrub")
        engine.stop(); assertSame("stopped")
    }

    func testAnotherSongAlwaysStartsAtTheBeginningWhateverTheLastOneWas() throws {
        let (transport, engine, fixture) = rig()
        _ = engine.play(fixture.urls[0])
        try transport.seek(toSeconds: 3)
        XCTAssertEqual(transport.position, 3)
        _ = engine.play(fixture.urls[1])
        XCTAssertEqual(transport.position, 0, "the new song starts at the beginning")
        XCTAssertEqual(engine.position, 0)
    }

    func testAPreparedSongIsShownPausedAtItsPlaceWithItsLength() {
        let (transport, engine, fixture) = rig()
        XCTAssertEqual(engine.prepare(fixture.urls[2], at: 2), .ready)
        XCTAssertEqual(transport.state, .paused)
        XCTAssertEqual(transport.position, 2)
        XCTAssertEqual(transport.duration, engine.duration)
        XCTAssertGreaterThan(transport.duration, 0)
        XCTAssertEqual(transport.nowPlaying, "track3.mp3")
        try? transport.play()
        XCTAssertEqual(transport.state, .playing, "Play carries on")
        XCTAssertEqual(transport.position, 2)
    }

    func testScrubbingSeeksTheEngineItselfSoThePositionShownIsAlwaysTheEnginesPosition() throws {
        let (transport, engine, fixture) = rig()
        _ = engine.play(fixture.urls[0])
        transport.beginScrub()
        for place in [1.0, 2.5, 3.5, 0.5] {
            try transport.seek(toSeconds: place)
            XCTAssertEqual(transport.position, place, "while the finger moves the position is the engine's position")
            XCTAssertEqual(engine.position, place)
        }
        try transport.endScrub(toSeconds: 0.5)
        XCTAssertEqual(engine.state, .playing)
    }
}

/// A source-level guard against the same mistake coming back: no screen or model may declare its own copy of the play
/// position, the scrub position or a resume point. Playback state is read from the engine where it is drawn.
@MainActor
final class NoCopiedPlaybackStateSourceTests: XCTestCase {
    private static let forbiddenNames = ["scrubPosition", "resumePoint", "displayedPosition", "lastKnownPosition", "elapsed", "currentTime", "playPosition"]

    func testNoSourceFileDeclaresItsOwnCopyOfPlaybackPosition() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var offences: [String] = []
        for folder in ["Sources/PlayawayCore", "ios/App"] {
            let files = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" && $0.lastPathComponent != "AudioBackend.swift" } ?? []   // the backend is the source itself
            XCTAssertFalse(files.isEmpty, "found sources under \(folder)")
            for file in files {
                let text = try String(contentsOf: file, encoding: .utf8)
                for name in Self.forbiddenNames where text.range(of: "\\b(var|let) \(name)\\b", options: .regularExpression) != nil {
                    offences.append("\(file.lastPathComponent) declares \(name)")
                }
            }
        }
        XCTAssertEqual(offences, [], "playback state must be read from the engine, never copied")
    }
}
