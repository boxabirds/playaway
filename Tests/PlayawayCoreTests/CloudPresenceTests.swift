import XCTest
@testable import PlayawayCore

final class CloudPresenceTests: XCTestCase {
    func testAFileOutsideICloudIsLocalOnly() {
        XCTAssertEqual(songPresence(isUbiquitous: false, downloadingStatus: nil), .localOnly)
        XCTAssertEqual(songPresence(isUbiquitous: false, downloadingStatus: ubiquitousStatusNotDownloaded), .localOnly)
    }

    func testCurrentAndDownloadedMeanOnThisDevice() {
        XCTAssertEqual(songPresence(isUbiquitous: true, downloadingStatus: ubiquitousStatusCurrent), .inCloudOnDevice)
        XCTAssertEqual(songPresence(isUbiquitous: true, downloadingStatus: ubiquitousStatusDownloaded), .inCloudOnDevice)
    }

    func testNotDownloadedMeansNotOnThisDevice() {
        XCTAssertEqual(songPresence(isUbiquitous: true, downloadingStatus: ubiquitousStatusNotDownloaded), .inCloudNotOnDevice)
    }

    func testAnUnknownStatusInICloudNeverBlocksPlaying() {
        XCTAssertEqual(songPresence(isUbiquitous: true, downloadingStatus: nil), .inCloudOnDevice)
        XCTAssertEqual(songPresence(isUbiquitous: true, downloadingStatus: "something new"), .inCloudOnDevice)
    }

    func testRowDisplayForEachPresenceWithNothingTracked() {
        XCTAssertEqual(SongRowCloudDisplay(presence: .localOnly, tracked: nil), SongRowCloudDisplay(icon: .crossedOut, dimmed: false, fraction: nil))
        XCTAssertEqual(SongRowCloudDisplay(presence: .inCloudOnDevice, tracked: nil), SongRowCloudDisplay(icon: .outline, dimmed: false, fraction: nil))
        XCTAssertEqual(SongRowCloudDisplay(presence: .inCloudNotOnDevice, tracked: nil), SongRowCloudDisplay(icon: .outline, dimmed: true, fraction: nil))
    }

    func testADownloadShowsThePieAndDimsTheRow() {
        let display = SongRowCloudDisplay(presence: .inCloudNotOnDevice, tracked: .downloading(0.4))
        XCTAssertEqual(display.icon, .pieDownload)
        XCTAssertTrue(display.dimmed)
        XCTAssertEqual(display.fraction, 0.4)
    }

    func testAFailureShowsTheExclamationMarkAndDimsTheRow() {
        let display = SongRowCloudDisplay(presence: .inCloudNotOnDevice, tracked: .failed)
        XCTAssertEqual(display.icon, .exclamation)
        XCTAssertTrue(display.dimmed)
        XCTAssertNil(display.fraction)
    }

    func testAFinishedDownloadFallsBackToTheFileSystem() {
        XCTAssertEqual(SongRowCloudDisplay(presence: .inCloudOnDevice, tracked: .onThisDevice),
                       SongRowCloudDisplay(icon: .outline, dimmed: false, fraction: nil))
    }

    func testACancelledDownloadIsDimmedAgain() {
        XCTAssertEqual(SongRowCloudDisplay(presence: .inCloudNotOnDevice, tracked: .notOnThisDevice).dimmed, true)
    }

    func testTheTapForEachIconMatchesTheSharedRule() {
        XCTAssertEqual(cloudIconTapAction(state: SongRowCloudDisplay(presence: .inCloudNotOnDevice, tracked: .downloading(0.1)).icon, kind: .song), .cancelDownload)
        XCTAssertEqual(cloudIconTapAction(state: SongRowCloudDisplay(presence: .inCloudNotOnDevice, tracked: .failed).icon, kind: .song), .retryDownload)
    }
}
