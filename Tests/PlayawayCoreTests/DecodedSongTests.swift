import XCTest
@testable import PlayawayCore

/// Owner's list: the scrub loop on the iPad is stranger the further along the song. Cutting snippets from a song decoded once
/// is the same cost and the same exact place anywhere in it.
final class DecodedSongTests: XCTestCase {
    private var song: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/long30.mp3")
    }

    private func ramp(_ count: Int) -> DecodedSong {
        DecodedSong(url: song, sampleRate: 1000, channels: [(0..<count).map { Int16($0 % 30000) }, (0..<count).map { Int16(-($0 % 30000)) }])
    }

    func testTheWholeFileIsDecodedWithItsRealLength() throws {
        let decoded = try XCTUnwrap(DecodedSong.decode(song))
        XCTAssertEqual(Double(decoded.frameCount) / decoded.sampleRate, 30, accuracy: 0.2)
        XCTAssertGreaterThanOrEqual(decoded.channels.count, 1)
        XCTAssertTrue(decoded.channels.allSatisfy { $0.count == decoded.frameCount }, "every channel has the same length")
    }

    func testAMissingFileDoesNotDecode() { XCTAssertNil(DecodedSong.decode(URL(fileURLWithPath: "/nonexistent.mp3"))) }

    func testADecodeThatIsNoLongerWantedStopsAndGivesNothing() { XCTAssertNil(DecodedSong.decode(song) { false }) }

    func testALoopIsTheAskedLengthAndStartsAtTheAskedPlaceWhereverInTheSong() {
        let decoded = ramp(10_000)
        for place in [0, 1234, 5000, 9000] {
            let loop = try! XCTUnwrap(decoded.loop(startFrame: place, loopFrames: 500, fadeFrames: 50))
            XCTAssertEqual(loop.count, 2)
            XCTAssertEqual(loop[0].count, 500, "every loop has the length asked, near the start or deep in the song")
            // After the blended opening the samples are the song's own, sample for sample.
            XCTAssertEqual(loop[0][100], Float(Int16((place + 100) % 30000)) / 32768, accuracy: 1e-6)
            XCTAssertEqual(loop[1][499], Float(-Int16((place + 499) % 30000)) / 32768, accuracy: 1e-6)
        }
    }

    func testTheEndOfALoopIsBlendedIntoItsStartSoThePointCannotClick() {
        let decoded = DecodedSong(url: song, sampleRate: 1000, channels: [(0..<2000).map { _ in 16384 }])
        let loop = try! XCTUnwrap(decoded.loop(startFrame: 100, loopFrames: 500, fadeFrames: 50))
        // Equal-power blending of two equal values rises to 1.41 times at the middle; never below the sound, never above that.
        XCTAssertTrue((0.49...0.72).contains(loop[0][0]) && (0.49...0.72).contains(loop[0][25]), "the blend stays near the sound: \(loop[0][0]) \(loop[0][25])")
        XCTAssertEqual(loop[0][200], 0.5, accuracy: 1e-6, "outside the blend it is the song's own")
    }

    func testALoopNearTheEndOfTheSongIsShorterButStillMade() {
        let decoded = ramp(1000)
        let loop = try! XCTUnwrap(decoded.loop(startFrame: 900, loopFrames: 500, fadeFrames: 50))
        XCTAssertEqual(loop[0].count, 100, "only 100 frames remain")
    }

    func testAPlaceAtOrPastTheEndOrBeforeTheStartMakesNoLoop() {
        let decoded = ramp(1000)
        XCTAssertNil(decoded.loop(startFrame: 1000, loopFrames: 100, fadeFrames: 10))
        XCTAssertNil(decoded.loop(startFrame: 5000, loopFrames: 100, fadeFrames: 10))
        XCTAssertNil(decoded.loop(startFrame: -1, loopFrames: 100, fadeFrames: 10))
        XCTAssertNil(decoded.loop(startFrame: 0, loopFrames: 0, fadeFrames: 10))
    }
}
