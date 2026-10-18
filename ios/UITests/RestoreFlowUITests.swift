import XCTest

/// Story 41: a playlist from another device whose songs are in iCloud Drive/Mixdowns. This device may not read that
/// folder yet, so every such song shows a locked cloud, one banner counts them, and Restore explains the one step the
/// system needs (the chooser itself cannot be driven by a test: in the fake drive a launch argument names what it
/// would return). Songs are then found again, counted honestly, and kept across launches.
final class RestoreFlowUITests: XCTestCase {
    static let arguments = ["-PlayawaySeedDemo", "-PlayawayFakeCloud", "-PlayawayFakeDrive", "-PlayawaySeedDrivePlaylist"]

    /// On the iPad the sidebar is a column only in landscape; portrait folds it behind a button.
    override func setUp() {
        continueAfterFailure = false
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
    }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = Self.arguments + extra; app.launch(); return app
    }
    private func cloud(_ app: XCUIApplication, _ row: String) -> XCUIElement { app.tables["song-table"].cells[row].buttons["cloud-icon"] }
    private func isLocked(_ app: XCUIApplication, _ row: String) -> Bool { cloud(app, row).exists && (cloud(app, row).value as? String) == "locked" }
    private func openPicks(_ app: XCUIApplication) {
        if app.tables["song-table"].cells["Demo Drive"].waitForExistence(timeout: 5) { return }
        XCTAssertTrue(app.staticTexts["Mixdowns Picks"].waitForExistence(timeout: 15), "the playlist from the other device is listed")
        app.staticTexts["Mixdowns Picks"].tap()
        XCTAssertTrue(app.tables["song-table"].cells["Demo Drive"].waitForExistence(timeout: 15))
    }
    private func restore(_ app: XCUIApplication) {
        app.buttons["restore-button"].tap()
        XCTAssertTrue(app.buttons["restore-continue"].waitForExistence(timeout: 5), "the explanation comes before the chooser")
        app.buttons["restore-continue"].tap()
    }
    private func dismissAlert(_ app: XCUIApplication, containing text: String) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        XCTAssertTrue(alert.staticTexts.allElementsBoundByIndex.contains { $0.label.contains(text) }, alert.debugDescription)
        alert.buttons.firstMatch.tap()
    }

    func testRestoreOnceThenPlayAndStillPlayAfterARelaunch() {               // TC-50, TC-55, TC-56 (iPad), TC-75, TC-76, TC-54
        let app = launch(); openPicks(app)
        let banner = app.otherElements["restore-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5)); XCTAssertTrue(banner.label.contains("2 songs"), banner.label)
        XCTAssertTrue(isLocked(app, "Demo Drive") && isLocked(app, "Demo Live"), "every unfound song shows the locked cloud")
        let lockedHeight = app.tables["song-table"].cells["Demo Drive"].frame.height
        cloud(app, "Demo Drive").tap()                                       // a tap on a locked cloud is the banner's Restore
        XCTAssertTrue(app.buttons["restore-continue"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Pause"].exists, "a locked cloud never plays the song")
        app.buttons["restore-not-now"].tap()                                 // Not now changes nothing
        XCTAssertTrue(banner.waitForExistence(timeout: 3)); XCTAssertTrue(isLocked(app, "Demo Drive"))
        restore(app)
        dismissAlert(app, containing: "Restored 2 of 2 songs")
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5), "restored: the banner goes")
        XCTAssertFalse(isLocked(app, "Demo Drive") || isLocked(app, "Demo Live"))
        XCTAssertEqual(app.tables["song-table"].cells["Demo Drive"].frame.height, lockedHeight, accuracy: 1, "the cloud changed, the row did not")
        app.tables["song-table"].cells["Demo Drive"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10), "and plays")

        app.terminate()
        let again = launch(["-PlayawayKeepMemory"]); openPicks(again)
        XCTAssertFalse(again.otherElements["restore-banner"].waitForExistence(timeout: 3), "the permission is kept across launches")
        again.tables["song-table"].cells["Demo Live"].tap()
        XCTAssertTrue(again.buttons["Pause"].waitForExistence(timeout: 10), "still playable on the next launch")
    }

    func testAPartialRestoreCountsTheRestThenLocateFindsTheLastSong() {       // TC-52, TC-77, TC-58, TC-78
        let app = launch(["-PlayawayFakePick", "Mixdowns/Live"]); openPicks(app)
        restore(app)
        dismissAlert(app, containing: "Restored 1 of 2 songs")
        XCTAssertFalse(isLocked(app, "Demo Live"), "the song under the chosen folder is back")
        XCTAssertTrue(isLocked(app, "Demo Drive"), "the other stays locked")
        XCTAssertTrue(app.otherElements["restore-banner"].label.contains("1 song"), app.otherElements["restore-banner"].label)
        cloud(app, "Demo Drive").press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Locate…"].waitForExistence(timeout: 5), "long-press offers Locate")
        app.buttons["Locate…"].tap()
        XCTAssertTrue(app.otherElements["restore-banner"].waitForNonExistence(timeout: 5), "located: nothing is left to restore")
        app.tables["song-table"].cells["Demo Drive"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10), "the located song plays")
    }

    func testAFolderWithoutTheSongsIsSaidSoAndNothingIsKept() {              // TC-53
        let app = launch(["-PlayawayFakePick", "Empty"]); openPicks(app)
        restore(app)
        dismissAlert(app, containing: "None of the songs were in that folder")
        XCTAssertTrue(app.otherElements["restore-banner"].waitForExistence(timeout: 3), "still needs restoring")
        XCTAssertTrue(isLocked(app, "Demo Drive"))
    }

    func testCancellingTheChooserChangesNothing() {                          // TC-54
        let app = launch(["-PlayawayFakePick", "cancel"]); openPicks(app)
        restore(app)
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2), "no message for a cancel")
        XCTAssertTrue(app.otherElements["restore-banner"].exists); XCTAssertTrue(isLocked(app, "Demo Live"))
    }

    func testTheDeviceThatCanReadTheFolderIsNeverAskedAndAGoneSongSaysSo() { // TC-51
        let app = launch()
        XCTAssertTrue(app.staticTexts["Mixdowns Mixed"].waitForExistence(timeout: 15))
        app.staticTexts["Mixdowns Mixed"].tap()
        let table = app.tables["song-table"]
        XCTAssertTrue(table.cells["Demo Here"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.otherElements["restore-banner"].waitForExistence(timeout: 2), "one song is found here, so the folder is readable")
        XCTAssertFalse(isLocked(app, "Demo Renamed"))
        table.cells["Demo Renamed"].tap()
        dismissAlert(app, containing: "can't be found")
        table.cells["Demo Here"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10), "the song the device can open plays")
    }

    func testAPlaylistInThePlayawayFolderNeverAsks() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15))
        app.staticTexts["Demo"].tap()
        XCTAssertTrue(app.tables["song-table"].cells["Demo One"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.otherElements["restore-banner"].waitForExistence(timeout: 2))
    }

    func testAddingASongFromAnUncoveredFolderOffersTheWholeFolderOnce() {   // TC-63, TC-64
        let app = launch()
        XCTAssertTrue(app.staticTexts["Mixdowns Mixed"].waitForExistence(timeout: 15))
        app.staticTexts["Mixdowns Mixed"].tap()
        XCTAssertTrue(app.buttons["add-fake-drive-song"].waitForExistence(timeout: 10))
        app.buttons["add-fake-drive-song"].tap()
        let offer = app.alerts["Let Playaway use this whole folder?"]
        XCTAssertTrue(offer.waitForExistence(timeout: 5), "the offer names the folder")
        XCTAssertTrue(offer.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("Other") })
        offer.buttons["Not Now"].tap()
        XCTAssertTrue(app.tables["song-table"].cells["Demo Added"].waitForExistence(timeout: 5), "declining still adds the song")
        app.buttons["add-fake-drive-song"].tap()
        XCTAssertFalse(app.alerts["Let Playaway use this whole folder?"].waitForExistence(timeout: 2), "not offered again after a decline")
    }

    func testAcceptingTheFolderOfferKeepsThePermission() {                    // TC-63
        let app = launch()
        XCTAssertTrue(app.staticTexts["Mixdowns Mixed"].waitForExistence(timeout: 15))
        app.staticTexts["Mixdowns Mixed"].tap()
        XCTAssertTrue(app.buttons["add-fake-drive-song"].waitForExistence(timeout: 10))
        app.buttons["add-fake-drive-song"].tap()
        app.alerts["Let Playaway use this whole folder?"].buttons["Choose Folder"].tap()
        dismissAlert(app, containing: "can now use “Other”")
    }
}
