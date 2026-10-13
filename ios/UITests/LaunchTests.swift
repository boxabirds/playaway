import XCTest

@MainActor final class LaunchTests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/pa-\(name).png"))
    }

    func testCreateAPlaylistAndOpenIt() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 5))
        shot(app, "1-empty")
        app.buttons["New Playlist"].tap()
        let field = app.alerts.textFields["Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Morning \(Int.random(in: 100...999))")
        app.alerts.buttons["Create"].tap()
        XCTAssertTrue(app.buttons["Add Songs"].waitForExistence(timeout: 5))
        shot(app, "2-playlist")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 5))
        shot(app, "3-list")
    }
}

@MainActor final class PlaybackTests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/pa-\(name).png"))
    }

    func testPlaySongOpenCardAndPause() {
        let app = XCUIApplication(); app.launchArguments = ["-PlayawaySeedDemo"]; app.launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 8))
        app.staticTexts["Demo"].tap()
        let first = app.buttons["Demo One"]
        XCTAssertTrue(first.waitForExistence(timeout: 5)); shot(app, "p1-playlist")
        first.tap()
        let controller = app.descendants(matching: .any)["floating-controller"]
        XCTAssertTrue(controller.waitForExistence(timeout: 5)); shot(app, "p2-controller")
        XCTAssertTrue(app.buttons["Pause"].exists)
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 3))
        app.buttons["Play"].tap()
        controller.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["player-card"].waitForExistence(timeout: 3)); sleep(1); shot(app, "p3-card")
        XCTAssertTrue(app.buttons["Shuffle"].exists); XCTAssertTrue(app.buttons["Next"].exists)
    }
}
