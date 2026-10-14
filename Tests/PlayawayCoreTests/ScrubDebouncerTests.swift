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
