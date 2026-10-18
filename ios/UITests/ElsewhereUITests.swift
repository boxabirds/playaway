import XCTest

/// Story 42: a song a Mac added from a folder that is not in iCloud cannot be found on this device and never can be.
/// Its cloud is a cloud with a question mark; tapping it, or its row, says what happened and what to do. A song that
/// was on this device and is gone keeps its old behaviour.
final class ElsewhereUITests: XCTestCase {
    static let arguments = ["-PlayawaySeedDemo", "-PlayawayFakeCloud", "-PlayawaySeedElsewherePlaylist", "-PlayawaySeedGoneSong"]
    static let message = "This was added to the playlist from another device and can't be found here. Suggestion: go back to that device and add it to iCloud so it can be accessed from here."

    override func setUp() {
        continueAfterFailure = false
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
    }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    private func open(_ playlist: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = Self.arguments; app.launch()
        XCTAssertTrue(app.staticTexts[playlist].waitForExistence(timeout: 15))
        app.staticTexts[playlist].tap()
        XCTAssertTrue(app.tables["song-table"].waitForExistence(timeout: 15))
        return app
    }
    private func cloud(_ app: XCUIApplication, _ row: String) -> XCUIElement { app.tables["song-table"].cells[row].buttons["cloud-icon"] }
    private func expectMessage(_ app: XCUIApplication) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        XCTAssertTrue(alert.staticTexts.allElementsBoundByIndex.contains { $0.label == Self.message }, alert.debugDescription)
        XCTAssertFalse(app.buttons["Pause"].exists, "nothing plays")
        alert.buttons["OK"].tap()
    }

    func testEveryUnfoundSongShowsTheQuestionCloudInAnOrdinaryRow() {              // TC-30, TC-34 on the iPad
        let app = open("From Mac Music")
        let table = app.tables["song-table"]
        XCTAssertTrue(table.cells["Elsewhere One"].waitForExistence(timeout: 10))
        XCTAssertEqual(cloud(app, "Elsewhere One").value as? String, "elsewhere")
        XCTAssertEqual(cloud(app, "Elsewhere Two").value as? String, "elsewhere")
        XCTAssertNotEqual(cloud(app, "Elsewhere Here").value as? String, "elsewhere", "the song that is here is not marked")
        XCTAssertEqual(table.cells["Elsewhere One"].frame.height, table.cells["Elsewhere Here"].frame.height, accuracy: 1, "no added text or height")
    }

    func testTappingTheCloudSaysWhatToDo() {                                         // TC-31
        let app = open("From Mac Music")
        XCTAssertTrue(cloud(app, "Elsewhere One").waitForExistence(timeout: 10))
        cloud(app, "Elsewhere One").tap()
        expectMessage(app)
    }

    func testTappingTheRowSaysTheSameNotTheOldMovedOrDeletedText() {                 // TC-32
        let app = open("From Mac Music")
        XCTAssertTrue(app.tables["song-table"].cells["Elsewhere Two"].waitForExistence(timeout: 10))
        app.tables["song-table"].cells["Elsewhere Two"].tap()
        expectMessage(app)
    }

    func testASongDeletedOnThisDeviceKeepsTheOldMessageAndNoQuestionMark() {         // TC-33
        let app = open("Demo")
        let table = app.tables["song-table"]
        XCTAssertTrue(table.cells["Gone Song"].waitForExistence(timeout: 10))
        XCTAssertFalse(cloud(app, "Gone Song").exists, "no cloud for a song that was here and is gone")
        table.cells["Gone Song"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        XCTAssertTrue(alert.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("can't be found") && $0.label.contains("moved, renamed or deleted") }, alert.debugDescription)
    }
}
