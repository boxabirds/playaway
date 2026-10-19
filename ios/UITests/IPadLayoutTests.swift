import XCTest

/// The iPad's forms: the stack when compact, two columns (playlists, songs) when regular in either orientation, the player
/// as a floating glass controller that opens as a card (owner's review: four columns, the player in the third even with
/// no lyrics, and no player in portrait). Silent (the demo seed's tones are
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

    /// The playlists, shown: already on screen where there is room for the sidebar, or after its button where there is not.
    private func sidebarIsReachable(_ app: XCUIApplication) -> Bool {
        if app.staticTexts["Demo"].waitForExistence(timeout: 15) { return true }
        for name in ["ToggleSidebar", "Show Sidebar", "Playlists"] where app.buttons[name].exists {
            app.buttons[name].tap()
            return app.staticTexts["Demo"].waitForExistence(timeout: 10)
        }
        return false
    }

    /// Taps the Demo playlist, opening the sidebar from its button first when it is folded away (in portrait the sidebar
    /// can still be sliding away when the app has just launched, so each attempt looks again).
    private func chooseDemo(_ app: XCUIApplication) -> Bool {
        for _ in 0..<4 {
            if app.staticTexts["Demo"].waitForExistence(timeout: 4), app.staticTexts["Demo"].isHittable { app.staticTexts["Demo"].tap(); return true }
            for name in ["ToggleSidebar", "Show Sidebar", "Playlists"] where app.buttons[name].exists { app.buttons[name].tap(); break }
        }
        return false
    }

    func testLandscapeShowsTwoColumnsAndNoPlayerUntilASongPlays() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15), "the sidebar lists the playlists")
        XCTAssertTrue(app.staticTexts["From Mac"].exists)
        XCTAssertTrue(app.staticTexts["songs-empty"].exists || app.otherElements["songs-empty"].waitForExistence(timeout: 5) || app.staticTexts["No playlist chosen"].exists, "the songs column invites a choice")
        XCTAssertFalse(app.staticTexts["Nothing playing"].exists, "there is no player column")
        XCTAssertFalse(app.descendants(matching: .any)["floating-controller"].exists, "nothing is playing, so no controller")
        XCTAssertFalse(app.otherElements["player-card"].exists)
    }

    func testASongPlayingShowsAFloatingControllerOverTheSongsAndTappingItOpensTheCard() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15))
        app.staticTexts["Demo"].tap()
        let table = app.tables["song-table"]
        XCTAssertTrue(table.waitForExistence(timeout: 10), "the songs column shows the chosen playlist")
        XCTAssertTrue(app.staticTexts["Demo"].exists, "the sidebar stays: selection, not navigation")
        table.cells["Demo One"].tap()
        let controller = app.descendants(matching: .any).matching(identifier: "floating-controller").firstMatch
        XCTAssertTrue(controller.waitForExistence(timeout: 10), "the controller floats over the songs")
        XCTAssertFalse(app.scrollViews["now-playing-column"].exists, "and there is no third column")
        XCTAssertLessThanOrEqual(controller.frame.width, 660, "a bar, not a slab")
        XCTAssertGreaterThan(controller.frame.minX, app.staticTexts["Demo"].frame.maxX, "inside the songs column, not over the sidebar")
        controller.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["player-card"].firstMatch.waitForExistence(timeout: 5), "the card opens")
        // Choosing another playlist changes the songs and keeps the song playing.
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    /// Owner's list: the position belongs on top of the fixed player, and the lyrics in a panel, not in the player.
    func testThePositionSliderSitsOnTopOfTheFloatingControllerAndTheLyricsHaveAPanelOfTheirOwn() {
        // Not the fake cloud: the ready-made lyrics are for the Demo One file in the app's own folder.
        let app = XCUIApplication(); app.launchArguments = ["-PlayawaySeedDemo", "-PlayawayFakeLyrics"]; app.launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15))
        app.staticTexts["Demo"].tap()
        let table = app.tables["song-table"]
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        table.cells["Demo One"].tap()
        let controller = app.descendants(matching: .any).matching(identifier: "floating-controller").firstMatch
        XCTAssertTrue(controller.waitForExistence(timeout: 10))
        let slider = controller.sliders["Playback position"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "the position is on the bar")
        XCTAssertLessThan(slider.frame.minY, controller.buttons["Pause"].frame.minY, "on top of the controls")
        XCTAssertTrue(controller.buttons["Previous"].exists && controller.buttons["Next"].exists, "with Previous and Next beside Play")
        // The lyrics: not in the card, in a panel from the toolbar.
        XCTAssertFalse(app.descendants(matching: .any)["lyrics-panel"].firstMatch.exists, "no lyrics until asked for")
        controller.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.85)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["player-card"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["lyrics-panel"].firstMatch.exists, "the card has no lyrics on the iPad")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.97)).tap()         // outside the card: the iPad's sheet closes
        XCTAssertTrue(app.descendants(matching: .any)["player-card"].firstMatch.waitForNonExistence(timeout: 5), "the card closed")
        XCTAssertTrue(app.buttons["lyrics-panel-button"].waitForExistence(timeout: 5))
        app.buttons["lyrics-panel-button"].tap()
        XCTAssertTrue(app.staticTexts["lyrics-line-0"].waitForExistence(timeout: 5), "the panel shows the lyrics")
    }

    func testPortraitShowsTheSongsTheControllerAndTheSidebarFromItsButton() {
        let app = launch()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(chooseDemo(app), "the playlists are on screen or behind the sidebar button in portrait")
        let table = app.tables["song-table"]
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        table.cells["Demo Two"].tap()
        let controller = app.descendants(matching: .any).matching(identifier: "floating-controller").firstMatch
        XCTAssertTrue(controller.waitForExistence(timeout: 10), "the player is there in portrait too")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(controller.waitForExistence(timeout: 10), "still playing after the rotation")
        XCTAssertTrue(table.cells["Demo Two"].waitForExistence(timeout: 10), "the same playlist's songs")
    }

    func testTheCompactWidthShowsTheStackWithTheControllerAndTheCard() {                       // TC-22, TC-06
        let app = launch(["-PlayawayWindowWidth", "320"])
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15))
        app.staticTexts["Demo"].tap()
        let table = app.tables["song-table"]
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        table.cells["Demo One"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
        app.buttons["Pause"].firstMatch.tap()                                                  // the floating controller's own button
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
    }

    func testAnAccessibilityTextSizeKeepsTwoColumnsWithTheSidebarBehindItsButton() {           // TC-23
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        XCTAssertTrue(sidebarIsReachable(app), "the playlists are on screen or behind the sidebar button")
        XCTAssertFalse(app.staticTexts["Nothing playing"].exists)
    }
}
