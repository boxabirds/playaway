import XCTest

/// Story 38 on the iPad simulator (task 38.6): the three forms, selection that survives a change of form while a song
/// plays, the empty Now Playing column, the words beside or below the controls. Silent (the demo seed's tones are
/// amplitude 0). Run with PLAYAWAY_SIM_DEVICE="iPad Pro 13-inch (M5)" scripts/ios-ui-tests.sh -only-testing:PlayawayUITests/IPadLayoutTests
@MainActor final class IPadLayoutTests: XCTestCase {
    static let seed = ["-PlayawaySeedDemo", "-PlayawayFakeCloud", "-PlayawaySeedForeignPlaylist"]

    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the iPad's forms; the iPhone suite is TC-30")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Self.seed + extra
        app.launch()
        return app
    }

    func testLandscapeShowsThreeColumnsWithNothingPlaying() {                                  // TC-20, TC-28 (empty)
        let app = launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15), "the sidebar lists the playlists")
        XCTAssertTrue(app.staticTexts["From Mac"].exists)
        XCTAssertTrue(app.otherElements["now-playing-empty"].waitForExistence(timeout: 5) || app.staticTexts["Nothing playing"].waitForExistence(timeout: 5), "the player column is never blank")
        XCTAssertFalse(app.buttons["Pause"].exists)
        XCTAssertFalse(app.otherElements["player-card"].exists, "no sheet in regular width")
    }

    func testChoosingAPlaylistSelectsItAndASongPlaysInTheDetailColumn() {                     // TC-24, TC-25 (column), TC-11
        let app = launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15))
        app.staticTexts["Demo"].tap()
        let table = app.tables["song-table"]
        XCTAssertTrue(table.waitForExistence(timeout: 10), "the songs column shows the chosen playlist")
        XCTAssertTrue(app.staticTexts["Demo"].exists, "the sidebar stays: selection, not navigation")
        table.cells["Demo One"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10), "the song plays in the detail column")
        XCTAssertTrue(app.otherElements["now-playing-column"].exists || app.scrollViews["now-playing-column"].exists)
        XCTAssertFalse(app.otherElements["player-card"].exists, "never the sheet")
        // Choosing another playlist changes the middle and keeps the song playing.
        app.staticTexts["From Mac"].tap()
        XCTAssertTrue(table.cells["Mac One"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Pause"].exists, "still playing")
    }

    func testRotatingToPortraitKeepsTheSongAndThePlaylist() {                                  // TC-21
        let app = launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15))
        app.staticTexts["Demo"].tap()
        let table = app.tables["song-table"]
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        table.cells["Demo Two"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10), "still playing after the rotation")
        XCTAssertTrue(table.cells["Demo Two"].waitForExistence(timeout: 10), "the same playlist's songs")
        XCTAssertTrue(app.buttons["Playlists"].exists || app.buttons["ToggleSidebar"].exists || app.buttons["Show Sidebar"].exists, "the sidebar is a button in portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
    }

    func testTheCompactWidthShowsTheStackWithTheControllerAndTheCard() {                       // TC-22, TC-06
        let app = launch(["-PlayawayWindowWidth", "320"])
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15))
        app.staticTexts["Demo"].tap()
        let table = app.tables["song-table"]
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        table.cells["Demo One"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Nothing playing"].exists, "no empty column in the stack")
        app.buttons["Pause"].firstMatch.tap()                                                  // the floating controller's own button
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
    }

    func testAnAccessibilityTextSizeShowsTwoColumns() {                                        // TC-23
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        XCTAssertTrue(app.staticTexts["Nothing playing"].waitForExistence(timeout: 15), "the player column is there")
        XCTAssertFalse(app.staticTexts["Demo"].exists, "two columns: the sidebar is folded away at an accessibility size")
        XCTAssertTrue(app.buttons["ToggleSidebar"].exists || app.buttons["Show Sidebar"].exists || app.buttons["Playlists"].exists, "and reachable from its button")
    }

    func testTheWordsSitBesideTheControlsInAWideColumnAndBelowInANarrowOne() {                 // TC-25, TC-27
        let app = launch(["-PlayawayFakeLyrics"])
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15))
        app.staticTexts["Demo"].tap()
        let table = app.tables["song-table"]
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        table.cells["Demo One"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
        let left = app.otherElements["player-left-column"], words = app.otherElements["player-lyrics-column"]
        let column = app.scrollViews["now-playing-column"].firstMatch
        XCTAssertTrue(column.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(column.frame.width, 600, "a 13-inch landscape detail column is wide")
        XCTAssertTrue(left.waitForExistence(timeout: 5) && words.exists, "beside: the words have their own column")
        XCTAssertGreaterThan(words.frame.minX, left.frame.midX, "to the right of the controls")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
        XCTAssertTrue(column.waitForExistence(timeout: 5))
        let beside = column.frame.width >= 600
        XCTAssertEqual(app.otherElements["player-lyrics-column"].waitForExistence(timeout: 3), beside,
                       "the words follow the column's width (\(Int(column.frame.width)) pt): beside at 600 and up, below under it")
    }
}
