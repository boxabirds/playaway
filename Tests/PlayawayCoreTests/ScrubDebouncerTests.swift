import XCTest
@testable import PlayawayCore

@MainActor
final class ScrubDebouncerTests: XCTestCase {
    private let shortDelay: TimeInterval = 0.05
    private let waitPastDelay: UInt64 = 250_000_000

    func testRapidScrubsCommitOnlyTheLastPositionOnce() async throws {
        var committed: [Double] = []
        let debouncer = ScrubDebouncer(delay: shortDelay) { committed.append($0) }
        for second in stride(from: 1.0, through: 20.0, by: 1.0) { debouncer.scrub(to: second) }
        XCTAssertTrue(committed.isEmpty, "nothing is committed while the scrub is still moving")
        try await Task.sleep(nanoseconds: waitPastDelay)
        XCTAssertEqual(committed, [20.0])
    }

    func testFinishCommitsAtOnceAndCancelsThePendingScrub() async throws {
        var committed: [Double] = []
        let debouncer = ScrubDebouncer(delay: shortDelay) { committed.append($0) }
        debouncer.scrub(to: 5)
        debouncer.finish(at: 7)
        XCTAssertEqual(committed, [7.0])
        try await Task.sleep(nanoseconds: waitPastDelay)
        XCTAssertEqual(committed, [7.0], "the cancelled scrub must not commit afterwards")
    }

    func testFinishWithNoScrubStillCommitsOnce() {
        var committed: [Double] = []
        let debouncer = ScrubDebouncer(delay: shortDelay) { committed.append($0) }
        debouncer.finish(at: 3)
        XCTAssertEqual(committed, [3.0])
    }

    func testPausesLongerThanTheDelayCommitEachRestingPosition() async throws {
        var committed: [Double] = []
        let debouncer = ScrubDebouncer(delay: shortDelay) { committed.append($0) }
        debouncer.scrub(to: 4)
        try await Task.sleep(nanoseconds: waitPastDelay)
        debouncer.scrub(to: 9)
        try await Task.sleep(nanoseconds: waitPastDelay)
        XCTAssertEqual(committed, [4.0, 9.0])
    }

    func testDefaultDelayIsThreeTenthsOfASecond() {
        XCTAssertEqual(scrubDebounceSeconds, 0.3)
    }
}

@MainActor
final class ScrubDebouncerDuplicateSegmentTests: XCTestCase {
    private let shortDelay: TimeInterval = 0.05
    private let waitPastDelay: UInt64 = 250_000_000

    /// Reproduces "if the user drags and drops the slider, it plays a bit, then plays again when dropped but the same
    /// segment is duplicated": a pause during the drag seeks, and lifting the finger at the same place seeked again.
    func testLiftingTheFingerWhereTheScrubAlreadySoughtDoesNotSeekAgain() async throws {
        var committed: [Double] = []
        let debouncer = ScrubDebouncer(delay: shortDelay) { committed.append($0) }
        debouncer.scrub(to: 42)
        try await Task.sleep(nanoseconds: waitPastDelay)
        XCTAssertEqual(committed, [42], "the pause during the drag sought once")
        debouncer.finish(at: 42)
        XCTAssertEqual(committed, [42], "lifting the finger in the same place must not replay the segment")
    }

    func testLiftingTheFingerSomewhereNewStillSeeks() async throws {
        var committed: [Double] = []
        let debouncer = ScrubDebouncer(delay: shortDelay) { committed.append($0) }
        debouncer.scrub(to: 42)
        try await Task.sleep(nanoseconds: waitPastDelay)
        debouncer.finish(at: 50)
        XCTAssertEqual(committed, [42, 50])
    }

    func testANewScrubAfterALiftedFingerSeeksEvenToTheSamePlace() async throws {
        var committed: [Double] = []
        let debouncer = ScrubDebouncer(delay: shortDelay) { committed.append($0) }
        debouncer.scrub(to: 42)
        try await Task.sleep(nanoseconds: waitPastDelay)
        debouncer.finish(at: 42)
        debouncer.scrub(to: 42)          // a new drag that happens to start and stop at 42 after the song moved on
        debouncer.finish(at: 42)
        XCTAssertEqual(committed, [42, 42], "a new drag is a new request")
    }
}
