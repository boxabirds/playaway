import XCTest
@testable import PlayawayCore

/// Story 20 (and 31's download-on-play rule for every entry point): a playable track whose file is in iCloud but not
/// on this device is handed to the adapter for a download rather than played or marked unreadable; it plays once the
/// file is here; the play-through loop skips it, like a missing track, and asks for it.
final class DownloadBeforePlayTests: XCTestCase {
    private final class Asks { var urls: [URL] = [] }
    private var asks = Asks()

    private func rig(absent: Int) -> (PlayerRig, [URL]) {
        let rig = PlayerRig(fixture: PlaylistFixture(trackNames: ["track1.mp3", "track2.mp3", "track3.mp3"]))
        let gone = rig.fixture.urls[absent]
        rig.player.isOnDevice = { $0 != gone }
        let asks = Asks()
        self.asks = asks
        rig.player.wantsDownload = { _, url in asks.urls.append(url) }
        return (rig, rig.fixture.urls)
    }

    func testATrackNotOnTheDeviceIsHandedOverForDownloadAndNothingPlaysOrIsMarked() {
        let (rig, urls) = rig(absent: 1)
        rig.player.play(track: rig.playlist.tracks[1])
        XCTAssertEqual(asks.urls, [urls[1]])
        XCTAssertNil(rig.engine.currentURL, "nothing plays until the file is here")
        XCTAssertNotEqual(rig.marks.mark(of: rig.playlist.tracks[1]), .unreadable, "waiting for a download is not a fault")
        XCTAssertFalse(rig.player.isSessionActive)
    }

    func testOnceTheFileIsOnTheDeviceTheSameTrackPlays() {
        let (rig, urls) = rig(absent: 1)
        rig.player.play(track: rig.playlist.tracks[1])
        XCTAssertNil(rig.engine.currentURL)
        rig.player.isOnDevice = { _ in true }                               // the download finished
        rig.player.play(track: rig.playlist.tracks[1])
        XCTAssertEqual(rig.engine.currentURL, urls[1])
        XCTAssertEqual(asks.urls, [urls[1]], "asked once")
    }

    func testPlayingThroughSkipsATrackNotOnTheDeviceAndAsksForIt() {
        let (rig, urls) = rig(absent: 0)
        rig.player.start()
        XCTAssertEqual(rig.engine.currentURL, urls[1], "the first playable track plays")
        XCTAssertEqual(asks.urls, [urls[0]], "and the absent one is asked for")
        XCTAssertNotEqual(rig.marks.mark(of: rig.playlist.tracks[0]), .unreadable)
    }

    func testNextOntoATrackNotOnTheDeviceSkipsItAndAsksForIt() {
        let (rig, urls) = rig(absent: 1)
        rig.player.start()
        XCTAssertEqual(rig.engine.currentURL, urls[0])
        rig.player.next()
        XCTAssertEqual(rig.engine.currentURL, urls[2])
        XCTAssertEqual(asks.urls, [urls[1]])
    }
}
