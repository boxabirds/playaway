import XCTest
@testable import PlayawayCore

/// Story 31, tasks 31.6 and 31.10: the download-on-play coordinator driving the real shared player and playlist over
/// the repo's real audio fixtures, with a scripted download seam (no real iCloud). Playback starts only when a
/// download finishes for the song that is still current; a download, a cancel, a failure and every icon tap leave the
/// playlist, its order and every file untouched.
@MainActor
final class DownloadOnPlayIntegrationTests: XCTestCase {
    /// The scripted platform: records the start and cancel commands; which songs are on the device is the test's say.
    private final class ScriptedDownloader: SongDownloading {
        var started: [SongID] = [], cancelled: [SongID] = []
        func startDownload(of song: SongID) { started.append(song) }
        func cancelDownload(of song: SongID) { cancelled.append(song) }
    }

    /// The adapter's side of "start playback": the song id names a track of the real player.
    @MainActor private final class Starter: SongPlaybackStarting {
        var player: PlaylistPlayer!
        var tracks: [SongID: Track] = [:]
        private(set) var starts: [SongID] = []
        func startPlayback(of song: SongID) {
            starts.append(song)
            if let track = tracks[song] { player.play(track: track) }
        }
    }

    private var fixture: PlaylistFixture!
    private var engine: AVPlaybackEngine!
    private var player: PlaylistPlayer!
    private var downloader: ScriptedDownloader!
    private var starter: Starter!
    private var sut: DownloadOnPlayCoordinator!
    private var ids: [SongID] = []
    private var bytesBefore: [Data] = []

    override func setUp() async throws {
        fixture = PlaylistFixture(trackNames: ["track1.mp3", "track2.mp3", "track3.mp3"])
        engine = makeEngine()
        starter = Starter()
        let playlist = fixture.playlist
        player = PlaylistPlayer(playlist: { playlist }, settings: PlayModeSettings(store: PlayModeStore(defaults: isolatedDefaults())),
                                engine: engine, marks: ReadabilityMarkStore(), registry: ActiveSessionRegistry())
        starter.player = player
        ids = fixture.tracks.map { SongID($0.id.uuidString) }
        for (id, track) in zip(ids, fixture.tracks) { starter.tracks[id] = track }
        downloader = ScriptedDownloader()
        sut = DownloadOnPlayCoordinator(downloader: downloader, player: starter)
        bytesBefore = try fixture.urls.map { try Data(contentsOf: $0) }
    }

    private func assertNothingElseChanged(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(fixture.playlist.tracks, fixture.tracks, "the playlist and its order are unchanged", file: file, line: line)
        XCTAssertEqual(try fixture.urls.map { try Data(contentsOf: $0) }, bytesBefore, "every file is unchanged", file: file, line: line)
    }

    // MARK: Playback only at finish, only for the current song (TC-30, TC-31)

    func testASongOnTheDevicePlaysAtOnceThroughTheRealPlayer() {                                 // TC-01 with the real player
        sut.request(ids[0], source: .list, isOnDevice: true)
        XCTAssertEqual(engine.currentURL, fixture.urls[0])
        XCTAssertEqual(downloader.started, [])
        assertNothingElseChanged()
    }

    func testASongNotOnTheDevicePlaysOnlyWhenItsDownloadFinishesWhileStillCurrent() {              // TC-30
        sut.request(ids[1], source: .list, isOnDevice: false)
        XCTAssertNil(engine.currentURL, "nothing plays while it downloads")
        XCTAssertEqual(downloader.started, [ids[1]])
        sut.handle(.progress(ids[1], reportedPercent: 50))
        XCTAssertNil(engine.currentURL)
        sut.handle(.finished(ids[1]))
        XCTAssertEqual(engine.currentURL, fixture.urls[1], "it plays when it arrives")
        XCTAssertEqual(starter.starts, [ids[1]], "one start")
        assertNothingElseChanged()
    }

    func testAFinishForASongNoLongerCurrentIsKeptWithoutInterruptingWhatPlays() {                 // TC-30, TC-41
        sut.request(ids[1], source: .list, isOnDevice: false)
        sut.request(ids[0], source: .list, isOnDevice: true)
        XCTAssertEqual(engine.currentURL, fixture.urls[0])
        sut.handle(.finished(ids[1]))
        XCTAssertEqual(engine.currentURL, fixture.urls[0], "the song playing is not interrupted")
        XCTAssertEqual(sut.state(of: ids[1]), .onThisDevice, "the file is kept")
        XCTAssertEqual(starter.starts, [ids[0]])
        assertNothingElseChanged()
    }

    func testARequestForASongAlreadyDownloadingJoinsIt() {                                       // TC-31
        sut.request(ids[2], source: .list, isOnDevice: false)
        sut.request(ids[2], source: .next, isOnDevice: false)
        XCTAssertEqual(downloader.started, [ids[2]], "one download")
        sut.handle(.finished(ids[2]))
        XCTAssertEqual(engine.currentURL, fixture.urls[2])
        XCTAssertEqual(starter.starts, [ids[2]], "one start")
    }

    func testASlowDownloadNeverRemovesTheSongOrChangesAnything() {                                // TC-40, TC-45
        sut.request(ids[1], source: .autoAdvance, isOnDevice: false)
        for percent in stride(from: 0.0, through: 90, by: 10) { sut.handle(.progress(ids[1], reportedPercent: percent)) }
        XCTAssertEqual(sut.state(of: ids[1]), .downloading(0.9))
        XCTAssertNil(engine.currentURL)
        assertNothingElseChanged()
    }

    // MARK: Cancel, failure, retry (TC-12, TC-46, TC-11, TC-67, TC-62)

    func testACancelledDownloadPlaysNothingAndChangesNothing() {
        sut.request(ids[1], source: .list, isOnDevice: false)
        sut.cancel(ids[1])
        XCTAssertEqual(downloader.cancelled, [ids[1]])
        XCTAssertEqual(sut.state(of: ids[1]), .notOnThisDevice)
        sut.handle(.finished(ids[1]))                                       // a late finish after the cancel
        XCTAssertNil(engine.currentURL)
        XCTAssertEqual(starter.starts, [])
        assertNothingElseChanged()
    }

    func testAFailedDownloadPlaysNothingRetriesNothingAndChangesNothing() {
        sut.request(ids[1], source: .list, isOnDevice: false)
        sut.handle(.failed(ids[1]))
        XCTAssertEqual(sut.state(of: ids[1]), .failed)
        XCTAssertNil(engine.currentURL)
        XCTAssertEqual(downloader.started, [ids[1]], "no automatic retry")
        assertNothingElseChanged()
    }

    func testARetryPlaysOnlyAtFinishWhileStillCurrent() {                                        // TC-62, TC-30 extension
        sut.request(ids[1], source: .list, isOnDevice: false)
        sut.handle(.failed(ids[1]))
        sut.retry(ids[1])
        XCTAssertEqual(downloader.started, [ids[1], ids[1]])
        XCTAssertEqual(sut.state(of: ids[1]), .downloading(0))
        XCTAssertNil(engine.currentURL)
        sut.handle(.finished(ids[1]))
        XCTAssertEqual(engine.currentURL, fixture.urls[1])
        XCTAssertEqual(starter.starts, [ids[1]], "once")
        assertNothingElseChanged()
    }

    // MARK: Every icon tap, with the real player (TC-39, TC-59)

    func testEveryIconTapLeavesThePlaylistAndFilesUntouchedAndStartsNoPlaybackByItself() {
        // Crossed-out: only a dialog request, which is the caller's to show; nothing here moves.
        XCTAssertEqual(cloudIconTapAction(state: .crossedOut, kind: .song), .openSyncDialog(.song))
        XCTAssertEqual(cloudIconTapAction(state: .crossedOut, kind: .playlist), .openSyncDialog(.playlist))
        // Outline: nothing at all.
        XCTAssertEqual(cloudIconTapAction(state: .outline, kind: .song), CloudIconTapAction.none)
        // Pie of a download: the cancel command only.
        sut.request(ids[1], source: .list, isOnDevice: false)
        if cloudIconTapAction(state: .pieDownload, kind: .song) == .cancelDownload { sut.cancel(ids[1]) }
        XCTAssertEqual(downloader.cancelled, [ids[1]])
        XCTAssertNil(engine.currentURL)
        // Pie of a sync: the cancel request only (what a cancelled sync leaves behind is PRD open question 9).
        XCTAssertEqual(cloudIconTapAction(state: .pieSync, kind: .song), .cancelSync)
        // Exclamation mark: the start command only, then the pie.
        sut.request(ids[2], source: .list, isOnDevice: false)
        sut.handle(.failed(ids[2]))
        if cloudIconTapAction(state: .exclamation, kind: .song) == .retryDownload { sut.retry(ids[2]) }
        XCTAssertEqual(downloader.started, [ids[1], ids[2], ids[2]])
        XCTAssertEqual(sut.state(of: ids[2]), .downloading(0))
        XCTAssertNil(engine.currentURL, "no tap starts playback by itself")
        XCTAssertEqual(starter.starts, [])
        assertNothingElseChanged()
    }

    func testATapOnThePieThatArrivesAfterTheDownloadFinishedDoesNothing() {                       // TC-59
        sut.request(ids[1], source: .list, isOnDevice: false)
        sut.handle(.finished(ids[1]))
        XCTAssertEqual(engine.currentURL, fixture.urls[1])
        let iconNow: CloudIconState = sut.state(of: ids[1]).isDownloading ? .pieDownload : .outline
        XCTAssertEqual(cloudIconTapAction(state: iconNow, kind: .song), CloudIconTapAction.none)
        sut.cancel(ids[1])                                                  // even if it reached the coordinator
        XCTAssertEqual(downloader.cancelled, [])
        XCTAssertEqual(engine.currentURL, fixture.urls[1], "still playing")
    }
}
