import XCTest
import PlayawayCore

/// Story 38, task 38.2: the pure arrangement decisions, TC-01 to TC-15, written before the views use them.
final class IPadLayoutTests: XCTestCase {
    func testColumnPlanOverSizeClassTypeSizeAndWidth() {
        XCTAssertEqual(IPadLayout.columnPlan(width: nil, isAccessibilityTypeSize: false, windowWidth: 1366), .stack, "TC-01: nil is compact")
        XCTAssertEqual(IPadLayout.columnPlan(width: .regular, isAccessibilityTypeSize: false, windowWidth: 1366), .three, "TC-02")
        XCTAssertEqual(IPadLayout.columnPlan(width: .regular, isAccessibilityTypeSize: false, windowWidth: 999), .two, "TC-03: just under")
        XCTAssertEqual(IPadLayout.columnPlan(width: .regular, isAccessibilityTypeSize: false, windowWidth: 1000), .three, "TC-04: at the threshold")
        XCTAssertEqual(IPadLayout.columnPlan(width: .regular, isAccessibilityTypeSize: true, windowWidth: 1366), .two, "TC-05: the type size wins")
        XCTAssertEqual(IPadLayout.columnPlan(width: .compact, isAccessibilityTypeSize: false, windowWidth: 320), .stack, "TC-06")
        XCTAssertEqual(IPadLayout.columnPlan(width: .compact, isAccessibilityTypeSize: false, windowWidth: 1366), .stack, "TC-07: the size class wins over width")
        XCTAssertEqual(IPadLayout.columnPlan(width: .regular, isAccessibilityTypeSize: false, windowWidth: 0), .two, "TC-08: never three before a measurement")
        XCTAssertEqual(IPadLayout.threeColumnMinimumWidth, 1000)
    }

    /// The rig: a fixed width narrower than the limit stands for a compact window (Split View one-third is 320 pt).
    func testTheRigsFixedWidthReadsAsCompactBelowItsLimit() {
        XCTAssertEqual(IPadLayout.rigCompactMaximumWidth, 500)
        XCTAssertLessThan(320, IPadLayout.rigCompactMaximumWidth)
        XCTAssertGreaterThanOrEqual(1000, IPadLayout.rigCompactMaximumWidth)
    }

    func testPlayerLayoutBoundary() {
        XCTAssertEqual(IPadLayout.playerLayout(columnWidth: 599), .stacked, "TC-14")
        XCTAssertEqual(IPadLayout.playerLayout(columnWidth: 600), .sideBySide, "TC-15")
        XCTAssertEqual(IPadLayout.lyricsBesideMinimumWidth, 600)
    }

    func testSelectionMapsToThePathInTheStackAndToTheSidebarInColumns() {
        let url = URL(fileURLWithPath: "/tmp/Dinner.lplaylist")
        let stack = IPadLayout.selection(choosing: url, plan: .stack, cardOpen: true)
        XCTAssertEqual(stack, IPadLayout.Selection(selected: url, path: [url], cardOpen: true), "TC-10: the stack pushes; the card is left as it was")
        let columns = IPadLayout.selection(choosing: url, plan: .three, cardOpen: true)
        XCTAssertEqual(columns, IPadLayout.Selection(selected: url, path: [], cardOpen: false), "TC-11: regular width never pushes and closes the card")
        XCTAssertEqual(IPadLayout.selection(choosing: url, plan: .two, cardOpen: false).path, [])
        XCTAssertEqual(IPadLayout.selection(choosing: nil, plan: .stack, cardOpen: false), IPadLayout.Selection(selected: nil, path: [], cardOpen: false), "TC-12: cleared")
        XCTAssertEqual(IPadLayout.selection(choosing: nil, plan: .three, cardOpen: false).selected, nil)
    }
}
