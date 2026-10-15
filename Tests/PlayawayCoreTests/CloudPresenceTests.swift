import XCTest
@testable import PlayawayCore

final class CloudPresenceTests: XCTestCase {
    func testASongInsideThePlaywayFolderIsInICloudWhetherOrNotItIsOnThisDevice() {
        XCTAssertEqual(songPresence(isUbiquitous: true, downloadingStatus: ubiquitousStatusCurrent, isInPlaywayFolder: true), .inCloudOnDevice)
        XCTAssertEqual(songPresence(isUbiquitous: true, downloadingStatus: ubiquitousStatusDownloaded, isInPlaywayFolder: true), .inCloudOnDevice)
        XCTAssertEqual(songPresence(isUbiquitous: true, downloadingStatus: ubiquitousStatusNotDownloaded, isInPlaywayFolder: true), .inCloudNotOnDevice)
    }

    func testASongElsewhereInICloudDriveIsNotInICloudInTheOwnersSense() {
        // The owner's rule: in iCloud means inside the Playaway folder, nothing else.
        XCTAssertEqual(songPresence(isUbiquitous: true, downloadingStatus: ubiquitousStatusCurrent, isInPlaywayFolder: false), .localOnly)
        XCTAssertEqual(songPresence(isUbiquitous: true, downloadingStatus: nil, isInPlaywayFolder: false), .localOnly)
    }

    func testASongElsewhereInICloudDriveThatIsNotDownloadedIsStillNotOnTheDevice() {
        let presence = songPresence(isUbiquitous: true, downloadingStatus: ubiquitousStatusNotDownloaded, isInPlaywayFolder: false)
        XCTAssertEqual(presence, .localOnlyNotOnDevice)
        XCTAssertFalse(presence.isOnDevice)
    }

    func testAFileOutsideICloudIsLocalOnlyWhateverItsStatus() {
        XCTAssertEqual(songPresence(isUbiquitous: false, downloadingStatus: nil, isInPlaywayFolder: false), .localOnly)
        XCTAssertEqual(songPresence(isUbiquitous: false, downloadingStatus: ubiquitousStatusNotDownloaded, isInPlaywayFolder: false), .localOnly)
    }

    func testAnUnknownStatusNeverBlocksPlayingAFileThatIsThere() {
        XCTAssertTrue(songPresence(isUbiquitous: true, downloadingStatus: nil, isInPlaywayFolder: true).isOnDevice)
        XCTAssertTrue(songPresence(isUbiquitous: true, downloadingStatus: "something new", isInPlaywayFolder: true).isOnDevice)
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

    func testANotDownloadedSongOutsideThePlaywayFolderShowsTheCrossedOutCloudAndIsDimmed() {
        XCTAssertEqual(SongRowCloudDisplay(presence: .localOnlyNotOnDevice, tracked: nil),
                       SongRowCloudDisplay(icon: .crossedOut, dimmed: true, fraction: nil))
    }

    func testTheTapForEachIconMatchesTheSharedRule() {
        XCTAssertEqual(cloudIconTapAction(state: SongRowCloudDisplay(presence: .inCloudNotOnDevice, tracked: .downloading(0.1)).icon, kind: .song), .cancelDownload)
        XCTAssertEqual(cloudIconTapAction(state: SongRowCloudDisplay(presence: .inCloudNotOnDevice, tracked: .failed).icon, kind: .song), .retryDownload)
    }
}
