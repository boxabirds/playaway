import XCTest
@testable import PlayawayCore

final class SongRowActionsTests: XCTestCase {
    func testFirstSongCannotMoveUp() { XCTAssertEqual(songRowActions(index: 0, count: 5), [.moveDown, .remove]) }
    func testLastSongCannotMoveDown() { XCTAssertEqual(songRowActions(index: 4, count: 5), [.moveUp, .remove]) }
    func testMiddleSongCanMoveBothWays() { XCTAssertEqual(songRowActions(index: 2, count: 5), [.moveUp, .moveDown, .remove]) }
    func testOnlySongCanOnlyBeRemoved() { XCTAssertEqual(songRowActions(index: 0, count: 1), [.remove]) }
    func testOutOfRangeOffersNothing() {
        XCTAssertEqual(songRowActions(index: -1, count: 3), [])
        XCTAssertEqual(songRowActions(index: 3, count: 3), [])
        XCTAssertEqual(songRowActions(index: 0, count: 0), [])
    }
}
