import XCTest
@testable import LocalPlayer
@testable import PlayawayCore

/// Story 20, the Mac download source: the system's answers about a file (scripted here, no real iCloud) become the
/// shared presence and the shared download events, with no play, mapping or dimming logic of its own.
@MainActor
final class MacCloudSongsTests: XCTestCase {
    private var sut: MacCloudSongs!
    private var events: [DownloadEvent] = []
    private var readings: [String: UbiquitousReading] = [:]
    private var requested: [URL] = []
    private var clock = Date(timeIntervalSince1970: 1_000_000)
    private let url = URL(fileURLWithPath: "/tmp/mac-cloud-songs-test/song.mp3")
    private var song: SongID { MacSongs.id(for: url) }

    override func setUp() {
        sut = MacCloudSongs()
        sut.read = { [unowned self] in readings[$0.path] ?? UbiquitousReading() }
        sut.startDownloading = { [unowned self] in requested.append($0) }
        sut.now = { [unowned self] in clock }
        sut.onEvent = { [unowned self] in events.append($0) }
    }

    override func tearDown() { sut.cancelDownload(of: song) }

    // MARK: Presence (TC-53): the download status never changes whether a file is in iCloud

    func testAChangeOfDownloadStatusLeavesTheInICloudAnswerUnchanged() {
        readings[url.path] = UbiquitousReading(isUbiquitous: true, status: ubiquitousStatusNotDownloaded)
        XCTAssertEqual(sut.presence(of: url), .inCloudNotOnDevice)
        readings[url.path] = UbiquitousReading(isUbiquitous: true, status: ubiquitousStatusCurrent)
        XCTAssertEqual(sut.presence(of: url), .inCloudOnDevice)
        readings[url.path] = UbiquitousReading(isUbiquitous: false, status: ubiquitousStatusNotDownloaded)
        XCTAssertEqual(sut.presence(of: url), .localOnly, "a status without iCloud means nothing")
    }

    func testAnUnreadableFileIsLocalOnly() {
        XCTAssertEqual(sut.presence(of: url), .localOnly)
    }

    // MARK: Events (TC-78)

    func testAStartAsksTheSystemOnceAndWatchesTheFile() {
        sut.startDownload(of: song)
        XCTAssertEqual(requested, [url])
        XCTAssertTrue(sut.isWatching(song))
        XCTAssertEqual(events, [], "no event until the system says something")
    }

    func testAStartTheSystemRefusesIsAFailure() {
        sut.startDownloading = { _ in throw CocoaError(.fileNoSuchFile) }
        sut.startDownload(of: song)
        XCTAssertEqual(events, [.failed(song)])
        XCTAssertFalse(sut.isWatching(song))
    }

    func testProgressThenFinishedReachTheCoordinatorAsTheMatchingEventsOnce() {
        sut.startDownload(of: song)
        readings[url.path] = UbiquitousReading(isUbiquitous: true, status: ubiquitousStatusNotDownloaded, isDownloading: true)
        sut.poll(song)
        XCTAssertEqual(events, [.progress(song, reportedPercent: nil)], "the system gives no percent, so none is invented")
        readings[url.path] = UbiquitousReading(isUbiquitous: true, status: ubiquitousStatusCurrent)
        sut.poll(song)
        sut.poll(song)                                                     // a late tick after the finish
        XCTAssertEqual(events, [.progress(song, reportedPercent: nil), .finished(song)])
        XCTAssertFalse(sut.isWatching(song))
    }

    func testTheSystemsDownloadErrorIsAFailure() {
        sut.startDownload(of: song)
        readings[url.path] = UbiquitousReading(isUbiquitous: true, status: ubiquitousStatusNotDownloaded, hasError: true)
        sut.poll(song)
        XCTAssertEqual(events, [.failed(song)])
        XCTAssertFalse(sut.isWatching(song))
    }

    func testADownloadTheSystemStopsReportingIsAFailureAfterTheStallTimeout() {
        sut.startDownload(of: song)
        readings[url.path] = UbiquitousReading(isUbiquitous: true, status: ubiquitousStatusNotDownloaded, isDownloading: false)
        clock = clock.addingTimeInterval(stallTimeout - 1)
        sut.poll(song)
        XCTAssertEqual(events, [.progress(song, reportedPercent: nil)], "still within the timeout")
        clock = clock.addingTimeInterval(2)
        sut.poll(song)
        XCTAssertEqual(events, [.progress(song, reportedPercent: nil), .failed(song)])
    }

    func testACancelStopsWatchingSoALaterAnswerIsNotReported() {
        sut.startDownload(of: song)
        sut.cancelDownload(of: song)
        XCTAssertFalse(sut.isWatching(song))
        readings[url.path] = UbiquitousReading(isUbiquitous: true, status: ubiquitousStatusCurrent)
        sut.poll(song)
        XCTAssertEqual(events, [])
    }
}
