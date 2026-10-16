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
