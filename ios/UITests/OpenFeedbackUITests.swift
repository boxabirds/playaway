import XCTest

/// Opening a playlist is work (reading the file, looking for every song). A tap must answer at once, and when the work
/// takes longer than a moment the row says so: the cloud becomes a pie and the subtitle counts the songs.
@MainActor final class OpenFeedbackUITests: XCTestCase {
    func testASlowOpenShowsAPieAndACountOnTheRowThenOpens() {
        let app = XCUIApplication(); app.launchArguments = ["-PlayawaySeedDemo", "-PlayawayOpenDelay", "4"]; app.launch()
        let row = app.staticTexts["Demo"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(app.otherElements["playlist-opening-pie"].waitForExistence(timeout: 2) || app.images["playlist-opening-pie"].waitForExistence(timeout: 1),
                      "after the short delay the cloud is a pie")
        let label = app.staticTexts["opening-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 2), "and the row counts the songs")
        XCTAssertTrue((label.label).hasPrefix("Loading "), "reads \"Loading n of m\", was \(label.label)")
        XCTAssertFalse(app.tables["song-table"].exists, "the playlist is not shown until it is ready")
        XCTAssertTrue(app.tables["song-table"].waitForExistence(timeout: 20), "then it opens")
        XCTAssertTrue(app.cells["Demo One"].waitForExistence(timeout: 5))
    }

    func testAFastOpenShowsNoProgressAtAll() {
        let app = XCUIApplication(); app.launchArguments = ["-PlayawaySeedDemo"]; app.launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15))
        app.staticTexts["Demo"].tap()
        XCTAssertTrue(app.tables["song-table"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["opening-label"].exists)
    }
}
