import XCTest
@testable import PlayawayCore

/// Story 42, icon.elsewhere: the question-mark cloud is one more state of the shared cloud icon.
final class ElsewhereCloudTests: XCTestCase {
    func testAnElsewhereSongShowsTheQuestionCloudWhateverElseIsKnown() {            // TC-10
        let display = try! XCTUnwrap(SongRowCloudDisplay.unfound(.elsewhere))
        XCTAssertEqual(display, SongRowCloudDisplay(icon: .elsewhere, dimmed: false, fraction: nil))
    }
    func testAGoneSongShowsNoCloudAsToday() {                                       // TC-11
        XCTAssertNil(SongRowCloudDisplay.unfound(.gone))
    }
    func testANeedsAccessSongShowsTheLockedCloudNeverTheQuestionMark() {            // TC-12
        XCTAssertEqual(SongRowCloudDisplay.unfound(.needsAccess)?.icon, .locked)
    }
    func testATapOnTheQuestionCloudExplainsAndNeverPlaysOrDownloads() {             // TC-13
        XCTAssertEqual(cloudIconTapAction(state: .elsewhere, kind: .song), .explainElsewhere)
    }
    func testEveryOtherStatesTapIsUnchanged() {                                     // TC-14
        XCTAssertEqual(cloudIconTapAction(state: .locked, kind: .song), .restoreAccess)
        XCTAssertEqual(cloudIconTapAction(state: .crossedOut, kind: .song), .openSyncDialog(.song))
        XCTAssertEqual(cloudIconTapAction(state: .exclamation, kind: .song), .retryDownload)
    }
    func testTheMessageIsTheOwnersWordsExactly() {                                  // TC-15
        XCTAssertEqual(addedElsewhereMessage, "This was added to the playlist from another device and can't be found here. Suggestion: go back to that device and add it to iCloud so it can be accessed from here.")
    }
}
