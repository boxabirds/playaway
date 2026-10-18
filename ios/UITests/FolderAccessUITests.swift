import XCTest

/// Story 40 (TC-30 to TC-33): a playlist from another device whose songs live in iCloud Drive/Mixdowns. This device
/// has not been allowed to read that folder, so the playlist says so and offers Allow; one tap (the fake drive grants
/// the folder in place of the system chooser, which a test cannot drive) and the songs show their cloud icons and play,
/// on this launch and the next. A playlist whose songs are in the Playaway folder never asks.
final class FolderAccessUITests: XCTestCase {
    static let arguments = ["-PlayawaySeedDemo", "-PlayawayFakeCloud", "-PlayawayFakeDrive", "-PlayawaySeedDrivePlaylist"]

    /// On the iPad the sidebar is a column only in landscape; portrait folds it behind a button.
    override func setUp() {
        continueAfterFailure = false
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
    }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    private func icon(_ app: XCUIApplication, row: String) -> XCUIElement {
        app.tables["song-table"].cells[row].buttons["cloud-icon"]
    }

    private func openPicks(_ app: XCUIApplication) {
        if app.tables["song-table"].cells["Demo Drive"].waitForExistence(timeout: 5) { return }
        XCTAssertTrue(app.staticTexts["Mixdowns Picks"].waitForExistence(timeout: 15), "the playlist from the other device is listed")
        app.staticTexts["Mixdowns Picks"].tap()
        XCTAssertTrue(app.tables["song-table"].cells["Demo Drive"].waitForExistence(timeout: 15))
    }

    func testAPlaylistWhoseSongsNeedAFolderAsksOnceThenPlays() {            // TC-30, TC-31, and TC-33 on the iPad
        let app = XCUIApplication(); app.launchArguments = Self.arguments; app.launch()
        openPicks(app)
        let notice = app.otherElements["access-notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "the playlist says its songs need the folder")
        XCTAssertTrue(notice.label.contains("Mixdowns"), notice.label)
        XCTAssertFalse(icon(app, row: "Demo Drive").exists, "nothing is known about a song that cannot be found")
        app.buttons["access-allow"].tap()
        XCTAssertTrue(notice.waitForNonExistence(timeout: 5), "allowed: the notice goes")
        XCTAssertTrue(icon(app, row: "Demo Drive").waitForExistence(timeout: 5), "the song is found under the allowed folder")
        app.tables["song-table"].cells["Demo Drive"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10), "and plays")
        XCTAssertFalse(app.alerts["Playlist"].exists, "no 'can't be found'")

        app.terminate()
        let again = XCUIApplication(); again.launchArguments = Self.arguments + ["-PlayawayKeepMemory"]; again.launch()
        openPicks(again)
        XCTAssertFalse(again.otherElements["access-notice"].waitForExistence(timeout: 3), "the grant is kept across launches")
        XCTAssertTrue(icon(again, row: "Demo Drive").waitForExistence(timeout: 5))
        again.tables["song-table"].cells["Demo Drive"].tap()
        XCTAssertTrue(again.buttons["Pause"].waitForExistence(timeout: 10), "still playable on the next launch")
    }

    func testAPlaylistInThePlayawayFolderNeverAsks() {                       // TC-32
        let app = XCUIApplication(); app.launchArguments = Self.arguments; app.launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15))
        app.staticTexts["Demo"].tap()
        XCTAssertTrue(app.tables["song-table"].cells["Demo One"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.otherElements["access-notice"].waitForExistence(timeout: 2), "songs on this device or in the Playaway folder need no permission")
    }
}
