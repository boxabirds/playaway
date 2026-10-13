import XCTest
@testable import PlayawayCore

final class CloudIconTapTests: XCTestCase {
    func testDecisionForEveryStateAndKind() {
        for kind in [SyncItemKind.song, .playlist] {
            XCTAssertEqual(cloudIconTapAction(state: .crossedOut, kind: kind), .openSyncDialog(kind))
            XCTAssertEqual(cloudIconTapAction(state: .outline, kind: kind), CloudIconTapAction.none)
            XCTAssertEqual(cloudIconTapAction(state: .pieDownload, kind: kind), .cancelDownload)
            XCTAssertEqual(cloudIconTapAction(state: .pieSync, kind: kind), .cancelSync)
            XCTAssertEqual(cloudIconTapAction(state: .exclamation, kind: kind), .retryDownload)
        }
    }

    func testTappableAreaIsAtLeast44Points() {
        XCTAssertGreaterThanOrEqual(minimumCloudIconTapSize.width, 44)
        XCTAssertGreaterThanOrEqual(minimumCloudIconTapSize.height, 44)
    }

    func testDrawnIconIsSmallerThanItsTappableArea() {
        XCTAssertLessThan(cloudIconDrawnSize.width, minimumCloudIconTapSize.width)
        XCTAssertLessThan(cloudIconDrawnSize.height, minimumCloudIconTapSize.height)
    }
}
