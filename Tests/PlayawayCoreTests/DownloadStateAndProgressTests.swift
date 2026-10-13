import XCTest
@testable import PlayawayCore

final class DownloadStateAndProgressTests: XCTestCase {
    func testRowDimmedExceptOnDevice() {
        XCTAssertFalse(DownloadState.onThisDevice.rowIsDimmed)
        for s in [DownloadState.notOnThisDevice, .downloading(0.5), .failed] { XCTAssertTrue(s.rowIsDimmed) }
    }

    func testOnlyFailedShowsExclamationMark() {
        XCTAssertTrue(DownloadState.failed.showsExclamationMark)
        for s in [DownloadState.onThisDevice, .notOnThisDevice, .downloading(0.1)] { XCTAssertFalse(s.showsExclamationMark) }
        XCTAssertEqual(DownloadState.failedAccessibilityLabel, "Download failed, tap to retry")
    }

    func testFractionClampedAndScaled() {
        let full = reportedPercentFullScale
        XCTAssertEqual(downloadFraction(reported: full / 2, isDownloading: true, previous: nil), 0.5)
        XCTAssertEqual(downloadFraction(reported: full * 3, isDownloading: true, previous: nil), 1)
        XCTAssertEqual(downloadFraction(reported: -5, isDownloading: true, previous: nil), 0)
    }

    func testNoProgressForNonNumberMissingOrNotDownloading() {
        XCTAssertNil(downloadFraction(reported: .nan, isDownloading: true, previous: nil))
        XCTAssertNil(downloadFraction(reported: .infinity, isDownloading: true, previous: nil))
        XCTAssertNil(downloadFraction(reported: nil, isDownloading: true, previous: nil))
        XCTAssertNil(downloadFraction(reported: 50, isDownloading: false, previous: nil))
    }

    func testNeverDecreases() {
        XCTAssertEqual(downloadFraction(reported: 10, isDownloading: true, previous: 0.6), 0.6)
    }
}
