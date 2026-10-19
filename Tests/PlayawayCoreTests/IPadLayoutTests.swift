import XCTest
import PlayawayCore

/// Story 38, task 38.2: the pure arrangement decisions, TC-01 to TC-15, written before the views use them.
final class IPadLayoutTests: XCTestCase {
    /// Owner's review of the first iPad design: four columns, the player in the third even with no lyrics, no way to see it
    /// in portrait. Now: the stack when compact, two columns whenever regular, whatever the orientation or type size.
    func testColumnPlanIsTheStackWhenCompactAndTwoColumnsWhenRegular() {
        XCTAssertEqual(IPadLayout.columnPlan(width: nil), .stack, "unknown is compact")
        XCTAssertEqual(IPadLayout.columnPlan(width: .compact), .stack)
        XCTAssertEqual(IPadLayout.columnPlan(width: .regular), .two)
    }

    /// The rig: a fixed width narrower than the limit stands for a compact window (Split View one-third is 320 pt).
    func testTheRigsFixedWidthReadsAsCompactBelowItsLimit() {
        XCTAssertEqual(IPadLayout.rigCompactMaximumWidth, 500)
        XCTAssertLessThan(320, IPadLayout.rigCompactMaximumWidth)
        XCTAssertGreaterThanOrEqual(1000, IPadLayout.rigCompactMaximumWidth)
    }

    func testSelectionMapsToThePathInTheStackAndToTheSidebarInColumns() {
        let url = URL(fileURLWithPath: "/tmp/Dinner.lplaylist")
        let stack = IPadLayout.selection(choosing: url, plan: .stack, cardOpen: true)
        XCTAssertEqual(stack, IPadLayout.Selection(selected: url, path: [url], cardOpen: true), "TC-10: the stack pushes; the card is left as it was")
        let columns = IPadLayout.selection(choosing: url, plan: .two, cardOpen: true)
        XCTAssertEqual(columns, IPadLayout.Selection(selected: url, path: [], cardOpen: false), "TC-11: regular width never pushes and closes the card")
        XCTAssertEqual(IPadLayout.selection(choosing: url, plan: .two, cardOpen: false).path, [])
        XCTAssertEqual(IPadLayout.selection(choosing: nil, plan: .stack, cardOpen: false), IPadLayout.Selection(selected: nil, path: [], cardOpen: false), "TC-12: cleared")
        XCTAssertEqual(IPadLayout.selection(choosing: nil, plan: .two, cardOpen: false).selected, nil)
    }
}
