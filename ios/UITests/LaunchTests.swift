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
        let first = app.tables["song-table"].cells["Demo One"]
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
        // The card's identifier lands on its first child (the playlist link), so its top is that element's top.
        let cardTop = app.descendants(matching: .any)["player-card"].firstMatch.frame.minY
        let controlsBottom = app.buttons["Next"].frame.maxY
        let screen = app.windows.firstMatch.frame
        let homeIndicatorAllowance: CGFloat = 120
        XCTAssertGreaterThan(cardTop, screen.height * 0.5, "card should hug its content, not fill the screen")
        XCTAssertGreaterThan(controlsBottom, screen.maxY - homeIndicatorAllowance, "controls should sit at the bottom edge")
    }
}

@MainActor final class EditingTests: XCTestCase {
    func testSwipeLeftRemovesASong() {
        let app = XCUIApplication(); app.launchArguments = ["-PlayawaySeedDemo"]; app.launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 8))
        app.staticTexts["Demo"].tap()
        let table = app.tables["song-table"]
        let two = table.cells["Demo Two"]
        XCTAssertTrue(two.waitForExistence(timeout: 5))
        XCTAssertEqual(table.cells.count, 5)
        two.swipeLeft()
        let remove = app.buttons["Remove from Playlist"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        remove.tap()
        XCTAssertFalse(table.cells["Demo Two"].waitForExistence(timeout: 2))
        XCTAssertEqual(table.cells.count, 4)
        XCTAssertTrue(app.staticTexts["4 songs"].exists)
    }
}

@MainActor final class ReorderTests: XCTestCase {
    private func order(_ table: XCUIElement) -> [String] {
        table.cells.allElementsBoundByIndex.sorted { $0.frame.minY < $1.frame.minY }.map(\.label)
    }

    private func drag(_ table: XCUIElement, _ from: String, toward target: String, below: Bool) {
        let src = table.cells[from].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let dst = table.cells[target].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.85 : 0.15))
        src.press(forDuration: 1.0, thenDragTo: dst, withVelocity: .slow, thenHoldForDuration: 0.5)
        sleep(1)
    }

    func testReorderStartMiddleAndEnd() {
        let app = XCUIApplication(); app.launchArguments = ["-PlayawaySeedDemo"]; app.launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 8))
        app.staticTexts["Demo"].tap()
        let table = app.tables["song-table"]
        XCTAssertTrue(table.cells["Demo Five"].waitForExistence(timeout: 5))
        let start = ["Demo One", "Demo Two", "Demo Three", "Demo Four", "Demo Five"]
        XCTAssertEqual(order(table), start)

        drag(table, "Demo One", toward: "Demo Five", below: true)              // first to the very end
        XCTAssertEqual(order(table), ["Demo Two", "Demo Three", "Demo Four", "Demo Five", "Demo One"])

        drag(table, "Demo One", toward: "Demo Two", below: false)              // last to the very beginning
        XCTAssertEqual(order(table), start)

        drag(table, "Demo Four", toward: "Demo Two", below: false)             // middle up
        XCTAssertEqual(order(table), ["Demo One", "Demo Four", "Demo Two", "Demo Three", "Demo Five"])

        drag(table, "Demo Two", toward: "Demo Five", below: true)              // middle down to the end
        XCTAssertEqual(order(table), ["Demo One", "Demo Four", "Demo Three", "Demo Five", "Demo Two"])
    }
}
