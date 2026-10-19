import XCTest
@testable import PlayawayCore

private final class FakeSeams: SongDownloading, SongPlaybackStarting {
    var started: [SongID] = [], cancelled: [SongID] = [], played: [SongID] = []
    func startDownload(of song: SongID) { started.append(song) }
    func cancelDownload(of song: SongID) { cancelled.append(song) }
    func startPlayback(of song: SongID) { played.append(song) }
}

@MainActor
final class DownloadOnPlayTests: XCTestCase {
    private let a = SongID("a"), b = SongID("b")
    private var seams = FakeSeams()
    private var sut: DownloadOnPlayCoordinator!

    override func setUp() {
        seams = FakeSeams()
        sut = DownloadOnPlayCoordinator(downloader: seams, player: seams)
    }

    // Audit I4: the screen is told to redraw only when an event changed something it shows.

    func testAProgressTickWithNoNewPercentageChangesNothingSoNothingIsRedrawn() {
        sut.request(a, source: .list, isOnDevice: false)
        XCTAssertFalse(sut.handle(.progress(a, reportedPercent: nil)), "the pie has not moved")
        XCTAssertFalse(sut.handle(.progress(a, reportedPercent: nil)))
        XCTAssertEqual(sut.state(of: a), .downloading(0))
    }

    func testAProgressTickWithANewPercentageIsAChange() {
        sut.request(a, source: .list, isOnDevice: false)
        XCTAssertTrue(sut.handle(.progress(a, reportedPercent: 50)))
        XCTAssertEqual(sut.state(of: a), .downloading(0.5), "50 of 100")
        XCTAssertFalse(sut.handle(.progress(a, reportedPercent: 50)), "the same percentage again is not")
    }

    func testFinishedAndFailedAreChangesAndALateReportForASongNotBeingFetchedIsNot() {
        sut.request(a, source: .list, isOnDevice: false)
        sut.request(b, source: .list, isOnDevice: false)
        XCTAssertTrue(sut.handle(.finished(a)))
        XCTAssertTrue(sut.handle(.failed(b)))
        XCTAssertFalse(sut.handle(.progress(a, reportedPercent: 90)), "a is on the device now")
        XCTAssertFalse(sut.handle(.finished(a)), "a second finish changes nothing")
        XCTAssertFalse(sut.handle(.failed(b)), "nor a second failure")
        XCTAssertFalse(sut.handle(.finished(SongID("never requested"))))
    }

    func testTheCurrentLoadingFollowsTheSongBeingWaitedForAndEndsWhenItArrivesOrFails() {
        XCTAssertNil(sut.currentLoading, "nothing asked for")
        sut.request(a, source: .list, isOnDevice: true)
        XCTAssertNil(sut.currentLoading, "on the device: nothing to wait for")
        sut.request(b, source: .list, isOnDevice: false)
        XCTAssertEqual(sut.currentLoading, 0, "waiting, no percentage yet")
        sut.handle(.progress(b, reportedPercent: 40))
        XCTAssertEqual(sut.currentLoading ?? -1, 0.4, accuracy: 1e-9)
        sut.request(a, source: .next, isOnDevice: true)
        XCTAssertNil(sut.currentLoading, "moved on to a song that is here")
        sut.request(b, source: .list, isOnDevice: false)
        sut.handle(.failed(b))
        XCTAssertNil(sut.currentLoading, "a failure is not loading")
    }

    func testSongOnDevicePlaysAtOnce() {
        sut.request(a, source: .list, isOnDevice: true)
        XCTAssertEqual(seams.played, [a]); XCTAssertTrue(seams.started.isEmpty)
        XCTAssertEqual(sut.state(of: a), .onThisDevice)
    }

    func testSongNotOnDeviceStartsDownloadAndDoesNotPlay() {
        sut.request(a, source: .list, isOnDevice: false)
        XCTAssertEqual(seams.started, [a]); XCTAssertTrue(seams.played.isEmpty)
        XCTAssertEqual(sut.current, a); XCTAssertEqual(sut.state(of: a), .downloading(0))
    }

    func testEverySourceBehavesTheSame() {
        for source in [PlayRequestSource.list, .next, .previous, .autoAdvance, .startPlaylist, .script] {
            let s = FakeSeams(); let c = DownloadOnPlayCoordinator(downloader: s, player: s)
            c.request(a, source: source, isOnDevice: false)
            XCTAssertEqual(s.started, [a], "\(source)"); XCTAssertTrue(s.played.isEmpty, "\(source)")
        }
    }

    func testFinishedWhileStillCurrentPlays() {
        sut.request(a, source: .list, isOnDevice: false)
        sut.handle(.finished(a))
        XCTAssertEqual(seams.played, [a]); XCTAssertEqual(sut.state(of: a), .onThisDevice)
    }

    func testFinishedWhileAnotherIsCurrentKeepsFileAndDoesNotPlay() {
        sut.request(a, source: .list, isOnDevice: false)
        sut.request(b, source: .next, isOnDevice: true)
        sut.handle(.finished(a))
        XCTAssertEqual(seams.played, [b]); XCTAssertEqual(sut.state(of: a), .onThisDevice)
        XCTAssertEqual(sut.current, b)
    }

    func testRequestForDownloadingSongJoinsIt() {
        sut.request(a, source: .list, isOnDevice: false)
        sut.request(a, source: .script, isOnDevice: false)
        XCTAssertEqual(seams.started, [a])
    }

    func testTransportPlayIgnoredWhileCurrentDownloads() {
        sut.request(a, source: .list, isOnDevice: false)
        XCTAssertEqual(sut.transportPlay(), .ignored)
        sut.handle(.finished(a))
        XCTAssertEqual(sut.transportPlay(), .proceed)
    }

    func testTransportPlayProceedsWithNoCurrentSong() {
        XCTAssertEqual(sut.transportPlay(), .proceed)
    }

    func testCancelReturnsToNotOnDeviceAndPlaysNothing() {
        sut.request(a, source: .list, isOnDevice: false)
        sut.cancel(a)
        XCTAssertEqual(seams.cancelled, [a]); XCTAssertEqual(sut.state(of: a), .notOnThisDevice)
        XCTAssertTrue(seams.played.isEmpty); XCTAssertTrue(sut.state(of: a).rowIsDimmed)
    }

    func testCancelWhenNotDownloadingDoesNothing() {
        sut.cancel(a)
        sut.request(b, source: .list, isOnDevice: true)
        sut.cancel(b)
        XCTAssertTrue(seams.cancelled.isEmpty); XCTAssertEqual(sut.state(of: b), .onThisDevice)
    }

    func testFailureGivesFailedStateAndNoPlaybackAndNoAutomaticRetry() {
        sut.request(a, source: .list, isOnDevice: false)
        sut.handle(.failed(a))
        XCTAssertEqual(sut.state(of: a), .failed); XCTAssertTrue(seams.played.isEmpty)
        XCTAssertEqual(seams.started, [a])   // no automatic retry
        XCTAssertTrue(sut.state(of: a).showsExclamationMark); XCTAssertTrue(sut.state(of: a).rowIsDimmed)
    }

    func testRetryRestartsOnlyAFailedSong() {
        sut.retry(a)
        XCTAssertTrue(seams.started.isEmpty)
        sut.request(a, source: .list, isOnDevice: false)
        sut.retry(a)                            // downloading: ignored
        XCTAssertEqual(seams.started, [a])
        sut.handle(.failed(a))
        sut.retry(a)
        XCTAssertEqual(seams.started, [a, a]); XCTAssertEqual(sut.state(of: a), .downloading(0))
    }

    func testProgressNeverDecreasesAndIgnoredWhenNotDownloading() {
        sut.handle(.progress(a, reportedPercent: 50))
        XCTAssertEqual(sut.state(of: a), .onThisDevice)
        sut.request(a, source: .list, isOnDevice: false)
        sut.handle(.progress(a, reportedPercent: 40))
        sut.handle(.progress(a, reportedPercent: 20))
        XCTAssertEqual(sut.state(of: a), .downloading(0.4))
        sut.handle(.progress(a, reportedPercent: nil))
        XCTAssertEqual(sut.state(of: a), .downloading(0.4))
    }

    func testLateEventsAfterCancelAreIgnored() {
        sut.request(a, source: .list, isOnDevice: false)
        sut.cancel(a)
        sut.handle(.finished(a)); sut.handle(.failed(a)); sut.handle(.progress(a, reportedPercent: 90))
        XCTAssertEqual(sut.state(of: a), .notOnThisDevice); XCTAssertTrue(seams.played.isEmpty)
    }

    func testFinishedTwiceStartsPlaybackOnce() {
        sut.request(a, source: .list, isOnDevice: false)
        sut.handle(.finished(a)); sut.handle(.finished(a))
        XCTAssertEqual(seams.played, [a])
    }

    func testProgressAfterFinishedChangesNothing() {
        sut.request(a, source: .list, isOnDevice: false)
        sut.handle(.finished(a)); sut.handle(.progress(a, reportedPercent: 30))
        XCTAssertEqual(sut.state(of: a), .onThisDevice)
    }

    func testCancelTwiceIssuesOneCommand() {
        sut.request(a, source: .list, isOnDevice: false)
        sut.cancel(a); sut.cancel(a)
        XCTAssertEqual(seams.cancelled, [a])
    }

    func testCancellingFirstDownloadLeavesSecondSongPlaying() {
        sut.request(a, source: .list, isOnDevice: false)
        sut.request(b, source: .list, isOnDevice: true)
        sut.cancel(a)
        XCTAssertEqual(sut.current, b); XCTAssertEqual(seams.played, [b])
    }

    func testRetryThenAnotherSongChosenKeepsFileWithoutPlaying() {
        sut.request(a, source: .list, isOnDevice: false)
        sut.handle(.failed(a)); sut.retry(a)
        sut.request(b, source: .list, isOnDevice: true)
        sut.handle(.finished(a))
        XCTAssertEqual(seams.played, [b]); XCTAssertEqual(sut.state(of: a), .onThisDevice)
    }

    func testRetryThatFailsAgainReturnsToFailedWithoutThirdAttempt() {
        sut.request(a, source: .list, isOnDevice: false)
        sut.handle(.failed(a)); sut.retry(a); sut.handle(.failed(a))
        XCTAssertEqual(sut.state(of: a), .failed); XCTAssertEqual(seams.started, [a, a])
        XCTAssertTrue(seams.played.isEmpty)
    }

    func testRetryThenFinishWhileStillCurrentPlays() {
        sut.request(a, source: .list, isOnDevice: false)
        sut.handle(.failed(a)); sut.retry(a); sut.handle(.finished(a))
        XCTAssertEqual(seams.played, [a])
    }
}
