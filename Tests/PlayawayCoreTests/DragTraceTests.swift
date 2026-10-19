import XCTest
@testable import PlayawayCore

final class DragTraceTests: XCTestCase {
    private func make() -> DragTrace {
        let fixed = Date(timeIntervalSince1970: 1_000_000)
        return DragTrace(clock: { fixed })
    }

    func testEventsAreKeptInOrderWithATimeEach() {
        let trace = make()
        trace.record("begin row 2")
        trace.record("end")
        XCTAssertEqual(trace.lines.count, 2)
        XCTAssertTrue(trace.lines[0].hasSuffix(" begin row 2"))
        XCTAssertTrue(trace.lines[1].hasSuffix(" end"))
        XCTAssertEqual(trace.lines[0].prefix(12).count, 12, "HH:mm:ss.SSS")
    }

    func testOnlyTheLastCapacityLinesAreKept() {
        let trace = make()
        for index in 0..<(DragTrace.capacity + 25) { trace.record("event \(index)") }
        XCTAssertEqual(trace.lines.count, DragTrace.capacity)
        XCTAssertTrue(trace.lines.first!.hasSuffix("event 25"))
        XCTAssertTrue(trace.lines.last!.hasSuffix("event \(DragTrace.capacity + 24)"))
    }

    func testClearEmptiesItAndTextJoinsTheLines() {
        let trace = make()
        trace.record("a"); trace.record("b")
        XCTAssertEqual(trace.text.split(separator: "\n").count, 2)
        trace.clear()
        XCTAssertTrue(trace.lines.isEmpty)
        XCTAssertEqual(trace.text, "")
    }

    func testRecordingFromSeveralThreadsLosesNothingUpToTheCapacity() {
        let trace = make()
        DispatchQueue.concurrentPerform(iterations: 40) { trace.record("t\($0)") }
        XCTAssertEqual(trace.lines.count, 40)
    }
}
