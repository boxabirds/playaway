import XCTest
@testable import PlayawayCore

/// The real preview player, on a real MP3 (the 30 s fixture).
final class AVLoopingPreviewTests: XCTestCase {
    private var song: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/long30.mp3")
    }

    func testItLoopsASnippetAndReportsAPlaceInsideIt() throws {
        let preview = AVLoopingPreview()
        XCTAssertTrue(preview.start(url: song, at: 10, length: 1))
        XCTAssertTrue(preview.isPlaying)
        Thread.sleep(forTimeInterval: 1.6)                      // longer than the snippet: it has looped at least once
        let place = try XCTUnwrap(preview.stop())
        XCTAssertGreaterThanOrEqual(place, 10)
        XCTAssertLessThanOrEqual(place, 11.05, "the place is always inside the snippet, however many times it has looped")
        XCTAssertFalse(preview.isPlaying)
        XCTAssertNil(preview.stop(), "stopping twice is harmless")
    }

    /// Audit F7: stopping slept on the calling thread for the length of the fade. Now the caller is released at once (and
    /// the loop is reported stopped at once), and starting again straight away is safe while the old one dies away.
    func testStoppingDoesNotHoldUpTheCallerAndAnImmediateRestartIsSafe() {
        let preview = AVLoopingPreview()
        let repeats = 20
        var heldUp = 0.0
        for _ in 0..<repeats {
            XCTAssertTrue(preview.start(url: song, at: 5, length: 0.5))
            let before = Date()
            XCTAssertNotNil(preview.stop())
            heldUp += Date().timeIntervalSince(before)
            XCTAssertFalse(preview.isPlaying, "stopped as far as the caller can see, immediately")
        }
        XCTAssertLessThan(heldUp, 0.1, "the 10 ms sleep per stop used to add up to at least 0.2 s here")
    }

    /// Audit (scrub): the first start of the loop took about 0.7 s here (engine start plus reading the snippet) and later ones
    /// 0.1 to 0.2 s, all on the main thread. Prepared in the background, the start is only scheduling the buffer.
    func testStartingAPreparedPlaceIsFastWhereAColdStartIsSlow() {
        let cold = AVLoopingPreview()
        let coldBegan = Date()
        XCTAssertTrue(cold.start(url: song, at: 7, length: 1))
        let coldTime = Date().timeIntervalSince(coldBegan)
        cold.stop(); cold.endSession()

        let preview = AVLoopingPreview()
        preview.prepare(url: song, at: 7, length: 1)
        Thread.sleep(forTimeInterval: 2)                           // the background work finishes
        let began = Date()
        XCTAssertTrue(preview.start(url: song, at: 7, length: 1))
        let preparedTime = Date().timeIntervalSince(began)
        XCTAssertTrue(preview.isPlaying)
        XCTAssertLessThan(preparedTime, 0.05, "a prepared start only schedules the buffer (cold took \(Int(coldTime * 1000)) ms)")
        XCTAssertLessThan(preparedTime, coldTime)
        preview.stop(); preview.endSession()
    }

    func testAnotherPlaceThanThePreparedOneIsStillPlayedFromWhereAskedNotFromTheOldPlace() throws {
        let preview = AVLoopingPreview()
        preview.prepare(url: song, at: 3, length: 1)
        XCTAssertTrue(preview.start(url: song, at: 15, length: 1))
        Thread.sleep(forTimeInterval: 0.3)
        let place = try XCTUnwrap(preview.stop())
        XCTAssertGreaterThanOrEqual(place, 15)
        XCTAssertLessThanOrEqual(place, 16.05)
        preview.endSession()
    }

    func testTheEngineSurvivesStartStopStartWithoutBeingRebuiltAndEndSessionLetsGo() {
        let preview = AVLoopingPreview()
        for place in [4.0, 9.0, 4.0] {
            XCTAssertTrue(preview.start(url: song, at: place, length: 0.5))
            XCTAssertNotNil(preview.stop())
        }
        preview.endSession()
        XCTAssertFalse(preview.isPlaying)
        XCTAssertTrue(preview.start(url: song, at: 4, length: 0.5), "usable again after a session ended")
        preview.stop(); preview.endSession()
    }

    func testASnippetAtTheVeryEndOfTheSongIsShorterButStillPlays() {
        let preview = AVLoopingPreview()
        XCTAssertTrue(preview.start(url: song, at: 29.7, length: 1))
        XCTAssertNotNil(preview.stop())
    }

    func testAPlaceBeyondTheEndOrAMissingFileFailsWithoutCrashing() {
        let preview = AVLoopingPreview()
        XCTAssertFalse(preview.start(url: song, at: 500, length: 1))
        XCTAssertFalse(preview.start(url: URL(fileURLWithPath: "/nonexistent.mp3"), at: 0, length: 1))
        XCTAssertFalse(preview.isPlaying)
    }
}
