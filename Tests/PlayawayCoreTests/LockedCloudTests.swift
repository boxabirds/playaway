import XCTest
@testable import PlayawayCore

/// Story 41, ios.recovery_ui: the locked cloud is one more state of the shared cloud icon.
final class LockedCloudTests: XCTestCase {
    func testNeedingAccessWinsOverEveryOtherInput() {                               // TC-70
        let presences: [SongPresence] = [.localOnly, .inCloudOnDevice, .inCloudNotOnDevice]
        let tracked: [DownloadState?] = [nil, .downloading(0.4), .failed]
        for presence in presences { for state in tracked {
            let display = SongRowCloudDisplay(needsAccess: true, presence: presence, tracked: state)
            XCTAssertEqual(display, SongRowCloudDisplay(icon: .locked, dimmed: false, fraction: nil), "\(presence) \(String(describing: state))")
        } }
    }
    func testNotNeedingAccessChangesNothing() {                                     // TC-71
        XCTAssertEqual(SongRowCloudDisplay(needsAccess: false, presence: .localOnly, tracked: nil).icon, .crossedOut)
        XCTAssertEqual(SongRowCloudDisplay(needsAccess: false, presence: .inCloudOnDevice, tracked: nil).icon, .outline)
        XCTAssertEqual(SongRowCloudDisplay(needsAccess: false, presence: .inCloudNotOnDevice, tracked: nil), SongRowCloudDisplay(icon: .outline, dimmed: true, fraction: nil))
        XCTAssertEqual(SongRowCloudDisplay(needsAccess: false, presence: .inCloudOnDevice, tracked: .failed).icon, .exclamation)
    }
    func testATapOnALockedCloudRestoresAccessAndNeverPlays() {                      // TC-72
        XCTAssertEqual(cloudIconTapAction(state: .locked, kind: .song), .restoreAccess)
    }
    func testEveryOtherStatesTapIsUnchanged() {                                     // TC-73
        XCTAssertEqual(cloudIconTapAction(state: .crossedOut, kind: .song), .openSyncDialog(.song))
        XCTAssertEqual(cloudIconTapAction(state: .outline, kind: .song), .none)
        XCTAssertEqual(cloudIconTapAction(state: .pieDownload, kind: .song), .cancelDownload)
        XCTAssertEqual(cloudIconTapAction(state: .pieSync, kind: .playlist), .cancelSync)
        XCTAssertEqual(cloudIconTapAction(state: .exclamation, kind: .song), .retryDownload)
    }
}
