import XCTest

/// The restore banner and the other bands inserted above a playlist's songs must stay readable in dark mode.
final class DarkModeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.appearance = .dark }
    override func tearDown() { XCUIDevice.shared.appearance = .light }

    func testTheBannerAndTheSheetKeepTheirOwnSurfaceInDarkMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PlayawaySeedDemo", "-PlayawayFakeCloud", "-PlayawayFakeDrive", "-PlayawaySeedDrivePlaylist"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Mixdowns Picks"].waitForExistence(timeout: 15))
        app.staticTexts["Mixdowns Picks"].tap()
        let banner = app.otherElements["restore-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/pa-dark-banner.png"))
        app.buttons["restore-button"].tap()
        XCTAssertTrue(app.buttons["restore-continue"].waitForExistence(timeout: 5))
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/pa-dark-explainer.png"))
    }

    /// What the row being dragged and the gap it leaves look like in dark mode, captured while the drag is held.
    func testTheDraggedRowAndItsGapInDarkMode() throws {
        let app = XCUIApplication(); app.launchArguments = ["-PlayawaySeedDemo"]; app.launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15)); app.staticTexts["Demo"].tap()
        let table = app.tables["song-table"]
        XCTAssertTrue(table.cells["Demo Three"].waitForExistence(timeout: 10))
        DispatchQueue.global().asyncAfter(deadline: .now() + 3.2) {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/pa-dark-drag.png"))
        }
        let src = table.cells["Demo Two"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let dst = table.cells["Demo Four"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        src.press(forDuration: 1.0, thenDragTo: dst, withVelocity: .slow, thenHoldForDuration: 4)
    }
}
