import XCTest
@testable import PlayawayCore

/// The coordinator driving the real shared player and playlist over real audio files, with a scripted download seam.
final class DownloadOnPlayIntegrationTests: XCTestCase {
    private final class ScriptedDownloader: SongDownloading {
        var started: [SongID] = []
        var cancelled: [SongID] = []
        func startDownload(of song: SongID) { started.append(song) }
        func cancelDownload(of song: SongID) { cancelled.append(song) }
    }

    /// Plays the chosen track through the real player, as the iPhone and the Mac do.
    private final class RealPlayback: SongPlaybackStarting {
        let rig: PlayerRig
        var tracksBySong: [SongID: Track] = [:]
        init(rig: PlayerRig) { self.rig = rig }
        func startPlayback(of song: SongID) { if let track = tracksBySong[song] { rig.player.play(track: track) } }
    }

    private struct Fixture {
        let rig = PlayerRig()
        let downloader = ScriptedDownloader()
        let playback: RealPlayback
        let coordinator: DownloadOnPlayCoordinator
        let songs: [SongID]

        init() {
            playback = RealPlayback(rig: rig)
            coordinator = DownloadOnPlayCoordinator(downloader: downloader, player: playback)
            songs = rig.fixture.urls.map { SongID($0.path) }
            for (song, track) in zip(songs, rig.fixture.tracks) { playback.tracksBySong[song] = track }
        }
        var started: [String] { rig.startedNames }
        var filesBefore: [Data] { rig.fixture.urls.map { try! Data(contentsOf: $0) } }
    }

    func testASongOnTheDevicePlaysAtOnceWithNoDownload() {
        let f = Fixture()
        f.coordinator.request(f.songs[0], source: .list, isOnDevice: true)
        XCTAssertEqual(f.started, ["track1.mp3"])
        XCTAssertTrue(f.downloader.started.isEmpty)
    }

    func testASongNotOnTheDevicePlaysOnlyWhenItsDownloadFinishes() {
        let f = Fixture()
        f.coordinator.request(f.songs[2], source: .list, isOnDevice: false)
        XCTAssertEqual(f.downloader.started, [f.songs[2]])
        XCTAssertTrue(f.started.isEmpty, "nothing plays while it downloads")
        XCTAssertEqual(f.rig.engine.state, .idle)
        f.coordinator.handle(.finished(f.songs[2]))
        XCTAssertEqual(f.started, ["track3.mp3"])
        XCTAssertEqual(f.rig.player.current, f.rig.fixture.tracks[2])
    }

    func testPlayIsIgnoredWhileTheCurrentSongDownloadsAndAllowedAfter() {
        let f = Fixture()
        f.coordinator.request(f.songs[1], source: .list, isOnDevice: false)
        XCTAssertEqual(f.coordinator.transportPlay(), .ignored)
        f.coordinator.handle(.finished(f.songs[1]))
        XCTAssertEqual(f.coordinator.transportPlay(), .proceed)
    }

    func testADownloadThatFinishesForAnotherSongKeepsTheFileAndPlaysNothing() {
        let f = Fixture()
        f.coordinator.request(f.songs[1], source: .list, isOnDevice: false)
        f.coordinator.request(f.songs[0], source: .list, isOnDevice: true)        // the person chose another song
        XCTAssertEqual(f.started, ["track1.mp3"])
        f.coordinator.handle(.finished(f.songs[1]))
        XCTAssertEqual(f.started, ["track1.mp3"], "the late download does not interrupt the song now playing")
        XCTAssertEqual(f.coordinator.state(of: f.songs[1]), .onThisDevice, "but the finished file is kept")
    }

    func testAFailedDownloadPlaysNothingAndRetryStartsItAgainWithoutAnAutomaticRetry() {
        let f = Fixture()
        f.coordinator.request(f.songs[3], source: .list, isOnDevice: false)
        f.coordinator.handle(.failed(f.songs[3]))
        XCTAssertEqual(f.coordinator.state(of: f.songs[3]), .failed)
        XCTAssertEqual(f.downloader.started.count, 1, "no automatic retry")
        XCTAssertTrue(f.started.isEmpty)
        f.coordinator.retry(f.songs[3])
        XCTAssertEqual(f.downloader.started.count, 2)
        f.coordinator.handle(.finished(f.songs[3]))
        XCTAssertEqual(f.started, ["track4.mp3"])
    }

    func testCancellingStopsTheDownloadAndNothingPlays() {
        let f = Fixture()
        f.coordinator.request(f.songs[4], source: .list, isOnDevice: false)
        f.coordinator.cancel(f.songs[4])
        XCTAssertEqual(f.downloader.cancelled, [f.songs[4]])
        XCTAssertEqual(f.coordinator.state(of: f.songs[4]), .notOnThisDevice)
        f.coordinator.handle(.finished(f.songs[4]))
        XCTAssertTrue(f.started.isEmpty)
    }

    func testEveryIconTapLeavesThePlaylistOrderAndFilesUnchanged() {
        let f = Fixture()
        let playlistBefore = f.rig.playlist
        let filesBefore = f.filesBefore
        // Cover every tap rule: a pie cancels, an exclamation mark retries, an outline does nothing.
        f.coordinator.request(f.songs[1], source: .list, isOnDevice: false)
        f.coordinator.cancel(f.songs[1])
        f.coordinator.request(f.songs[2], source: .list, isOnDevice: false)
        f.coordinator.handle(.failed(f.songs[2]))
        f.coordinator.retry(f.songs[2])
        f.coordinator.retry(f.songs[0])           // not failed: ignored
        f.coordinator.cancel(f.songs[0])          // not downloading: ignored
        XCTAssertEqual(f.rig.playlist, playlistBefore)
        XCTAssertEqual(f.filesBefore, filesBefore, "no audio file is changed by any icon tap")
    }

    func testARequestForASongAlreadyDownloadingJoinsThatDownloadInsteadOfStartingAnother() {         // TC-31
        let f = Fixture()
        f.coordinator.request(f.songs[2], source: .list, isOnDevice: false)
        f.coordinator.request(f.songs[2], source: .next, isOnDevice: false)
        XCTAssertEqual(f.downloader.started, [f.songs[2]], "one download, not two")
        f.coordinator.handle(.finished(f.songs[2]))
        XCTAssertEqual(f.started, ["track3.mp3"], "and it plays once")
    }

    func testASlowOrUnfinishedDownloadNeverRemovesTheSongFromThePlaylist() {                          // TC-45
        let f = Fixture()
        let before = f.rig.playlist
        f.coordinator.request(f.songs[1], source: .list, isOnDevice: false)
        f.coordinator.handle(.progress(f.songs[1], reportedPercent: nil))
        f.coordinator.handle(.progress(f.songs[1], reportedPercent: 40))
        XCTAssertEqual(f.rig.playlist, before)
        XCTAssertNotNil(f.rig.playlist.track(withID: f.rig.fixture.tracks[1].id))
    }

    func testARetryThatFinishesWhileItsSongIsStillCurrentStartsPlaybackOnce() {                       // TC-62
        let f = Fixture()
        f.coordinator.request(f.songs[3], source: .list, isOnDevice: false)
        f.coordinator.handle(.failed(f.songs[3]))
        f.coordinator.retry(f.songs[3])
        f.coordinator.handle(.finished(f.songs[3]))
        f.coordinator.handle(.finished(f.songs[3]))      // a repeated finish does nothing
        XCTAssertEqual(f.started, ["track4.mp3"], "playback starts once")
    }

    func testAFailureAndACancelLeavePlaylistOrderAndFilesUnchangedAndNeverPlay() {                    // TC-11, TC-12, TC-46, TC-67
        let f = Fixture()
        let playlistBefore = f.rig.playlist
        let filesBefore = f.filesBefore
        f.coordinator.request(f.songs[1], source: .list, isOnDevice: false)
        f.coordinator.handle(.failed(f.songs[1]))
        f.coordinator.request(f.songs[2], source: .list, isOnDevice: false)
        f.coordinator.cancel(f.songs[2])
        XCTAssertTrue(f.started.isEmpty)
        XCTAssertEqual(f.rig.playlist, playlistBefore)
        XCTAssertEqual(f.filesBefore, filesBefore)
    }
}
