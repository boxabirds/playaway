import XCTest
@testable import PlayawayCore

final class SongDragPolicyTests: XCTestCase {
    func testAnIPadSongCarriesItsFileSoThePlaylistsInTheSidebarCanTakeIt() { XCTAssertTrue(SongDragPolicy.offersFileURL(isPad: true)) }
    func testAnIPhoneSongCarriesOnlyItsIdSoNoDropExceptTheListsOwnCanClaimIt() { XCTAssertFalse(SongDragPolicy.offersFileURL(isPad: false)) }
}
