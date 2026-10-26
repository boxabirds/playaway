import XCTest
@testable import PlayawayCore

/// Story 43: when a missing song offers Choose Replacement, and when a found song says it was found under a new name.
final class SongReplacementTests: XCTestCase {
    let inDrive = TrackReference(bookmark: Data(), lastKnownPath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Mixdowns/a.mp3", fileName: "a.mp3")
    let onlyHere = TrackReference(bookmark: Data(), lastKnownPath: "/Users/someone/Music/a.mp3", fileName: "a.mp3")

    func testAGoneSongInICloudOffersAReplacement() {
        XCTAssertTrue(offersReplacement(.gone, for: inDrive))
    }

    func testASongThatIsNotMissingDoesNotOfferOne() {                                // TC-15
        XCTAssertFalse(offersReplacement(nil, for: inDrive))
    }

    func testASongWithNoPortableLocationDoesNotOfferOne() {                          // the choice is stored by portable location
        XCTAssertFalse(offersReplacement(.gone, for: onlyHere))
    }

    func testTheOtherKindsKeepTheirOwnWays() {                                       // locked has Locate, elsewhere has its message
        XCTAssertFalse(offersReplacement(.needsAccess, for: inDrive))
        XCTAssertFalse(offersReplacement(.elsewhere, for: inDrive))
    }

    func testAFoundFileWithAnotherNameIsReportedByItsName() {                        // TC-11
        XCTAssertEqual(foundUnderNewName(stored: "a.mp3", found: URL(fileURLWithPath: "/x/a (final).mp3")), "a (final).mp3")
    }

    func testTheSameNameIsNotReported() {
        XCTAssertNil(foundUnderNewName(stored: "a.mp3", found: URL(fileURLWithPath: "/x/a.mp3")))
    }

    func testOnlyTheLetterCaseDiffersIsNotReported() {
        XCTAssertNil(foundUnderNewName(stored: "A.MP3", found: URL(fileURLWithPath: "/x/a.mp3")))
    }

    func testNothingFoundReportsNothing() {
        XCTAssertNil(foundUnderNewName(stored: "a.mp3", found: nil))
    }
}
