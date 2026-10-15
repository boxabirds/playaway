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

@MainActor final class NavigationTests: XCTestCase {
    func testBackTitleAndTheCardLinkRecordsOneEntry() {
        let app = XCUIApplication(); app.launchArguments = ["-PlayawaySeedDemo"]; app.launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 8))
        app.staticTexts["Demo"].tap()
        XCTAssertTrue(app.tables["song-table"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars.buttons["Playlists"].exists, "back control is titled with where it returns to")
        app.tables["song-table"].cells["Demo One"].tap()
        let controller = app.descendants(matching: .any)["floating-controller"]
        XCTAssertTrue(controller.waitForExistence(timeout: 5))
        controller.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["player-card"].waitForExistence(timeout: 3))
        // The playlist is already shown, so the link records nothing: one Back reaches the Playlists screen.
        app.buttons["Demo"].firstMatch.tap()
        sleep(1)
        app.navigationBars.buttons["Playlists"].tap()
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 3), "one Back reaches the Playlists screen")
    }
}

@MainActor final class ListEndTests: XCTestCase {
    func testLastSongCanBeScrolledClearOfTheController() {
        let app = XCUIApplication(); app.launchArguments = ["-PlayawaySeedDemo", "-PlayawayLongList"]; app.launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 8))
        app.staticTexts["Demo"].tap()
        let table = app.tables["song-table"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        table.cells.element(boundBy: 0).tap()
        let controller = app.descendants(matching: .any)["floating-controller"]
        XCTAssertTrue(controller.waitForExistence(timeout: 5))
        app.buttons["Pause"].firstMatch.tap()    // paused, so a song starting afterwards can only come from the tap below
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 3))
        for _ in 0..<10 { table.swipeUp(velocity: .fast) }
        sleep(2)    // let the scrolling settle, so the tap selects a song instead of stopping the scroll
        // Tap just above the controller: after scrolling to the end, the last song (Demo Five) is what is there.
        let aboveController = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.width / 2, dy: controller.frame.minY - 25))
        aboveController.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5), "tapping the song just above the controller plays it")
    }
}

@MainActor final class RenameDeleteTests: XCTestCase {
    private func makePlaylist(_ app: XCUIApplication, _ name: String) {
        app.buttons["New Playlist"].tap()
        let field = app.alerts.textFields["Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.typeText(name)
        // The simulator sometimes ignores the first tap on an alert button while the keyboard is settling.
        for _ in 0..<3 where !app.buttons["Add Songs"].exists {
            if app.alerts.buttons["Create"].exists { app.alerts.buttons["Create"].tap() }
            _ = app.buttons["Add Songs"].waitForExistence(timeout: 4)
        }
        XCTAssertTrue(app.buttons["Add Songs"].waitForExistence(timeout: 15))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 15))
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    private func beginRename(_ app: XCUIApplication, row name: String) {
        app.staticTexts[name].press(forDuration: 1.2)
        app.buttons["Rename"].tap()
        XCTAssertTrue(app.textFields["rename-field"].waitForExistence(timeout: 15))
    }

    private var renameField: XCUIElement { XCUIApplication().textFields["rename-field"] }

    func testRenameFromTheListAndRefusals() {
        let app = XCUIApplication(); app.launchArguments = ["-PlayawaySeedDemo"]; app.launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15))
        let alpha = "Alpha"
        makePlaylist(app, alpha)

        // A name already used is refused: the panel comes back with the reason and the typed text.
        beginRename(app, row: alpha)
        replaceText(in: app.textFields["rename-field"], with: "Demo")
        app.navigationBars["Rename Playlist"].buttons["Rename"].tap()
        XCTAssertTrue(app.staticTexts["A playlist with that name already exists."].waitForExistence(timeout: 15))
        XCTAssertEqual(app.textFields["rename-field"].value as? String, "Demo", "the typed text is kept")

        // A name with a slash is refused.
        replaceText(in: app.textFields["rename-field"], with: "a/b")
        app.navigationBars["Rename Playlist"].buttons["Rename"].tap()
        XCTAssertTrue(app.staticTexts["A playlist name can't contain / or :."].waitForExistence(timeout: 15))

        // A good name renames it.
        replaceText(in: app.textFields["rename-field"], with: "Beta")
        app.navigationBars["Rename Playlist"].buttons["Rename"].tap()
        XCTAssertTrue(app.staticTexts["Beta"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts[alpha].exists)
    }

    func testRenameFromInsideAPlaylistKeepsTheSongs() {
        let app = XCUIApplication(); app.launchArguments = ["-PlayawaySeedDemo"]; app.launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15))
        app.staticTexts["Demo"].tap()
        XCTAssertTrue(app.tables["song-table"].waitForExistence(timeout: 15))
        app.buttons["playlist-name"].tap()
        XCTAssertTrue(app.textFields["rename-field"].waitForExistence(timeout: 15))
        replaceText(in: app.textFields["rename-field"], with: "Tunes")
        app.navigationBars["Rename Playlist"].buttons["Rename"].tap()
        let header = app.buttons["playlist-name"]
        expectation(for: NSPredicate(format: "label == 'Tunes'"), evaluatedWith: header)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(app.tables["song-table"].cells["Demo One"].exists, "the songs are still there")
        XCTAssertEqual(app.tables["song-table"].cells.count, 5)
    }

    func testDeleteAsksFirstAndCancelChangesNothing() {
        let app = XCUIApplication(); app.launchArguments = ["-PlayawaySeedDemo"]; app.launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15))
        makePlaylist(app, "Doomed")
        app.staticTexts["Doomed"].swipeLeft()
        app.buttons["Delete"].tap()
        let alert = app.alerts["Delete “Doomed”?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        XCTAssertTrue(alert.staticTexts["Only the playlist is deleted. Your songs are not."].exists)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Doomed"].exists, "cancel leaves it")
        app.staticTexts["Doomed"].swipeLeft()
        app.buttons["Delete"].tap()
        app.alerts["Delete “Doomed”?"].buttons["Delete"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.staticTexts["Doomed"])
        waitForExpectations(timeout: 15)
        XCTAssertTrue(app.staticTexts["Demo"].exists, "another playlist is untouched")
    }

    func testDeletingThePlayingPlaylistStopsThePlayer() {
        let app = XCUIApplication(); app.launchArguments = ["-PlayawaySeedDemo"]; app.launch()
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 15))
        app.staticTexts["Demo"].tap()
        app.tables["song-table"].cells["Demo One"].tap()
        let controller = app.descendants(matching: .any)["floating-controller"]
        XCTAssertTrue(controller.waitForExistence(timeout: 15))
        app.navigationBars.buttons["Playlists"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.tables["song-table"])
        waitForExpectations(timeout: 15)
        let row = app.staticTexts["Demo"]
        row.coordinate(withNormalizedOffset: CGVector(dx: 4, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: -4, dy: 0.5)))
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/pa-swiped.png"))
        app.buttons["Delete"].tap()
        app.alerts.buttons["Delete"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: controller)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(app.staticTexts["No Playlists"].waitForExistence(timeout: 15))
    }
}

@MainActor final class RememberTests: XCTestCase {
    func testRelaunchReturnsToThePlaylistAndSongAndPlace() {
        let first = XCUIApplication(); first.launchArguments = ["-PlayawaySeedDemo"]; first.launch()
        XCTAssertTrue(first.staticTexts["Demo"].waitForExistence(timeout: 8))
        first.staticTexts["Demo"].tap()
        first.tables["song-table"].cells["Demo Two"].tap()
        XCTAssertTrue(first.descendants(matching: .any)["floating-controller"].waitForExistence(timeout: 5))
        sleep(7)    // long enough for at least one periodic position save
        first.terminate()

        let second = XCUIApplication(); second.launchArguments = ["-PlayawaySeedDemo", "-PlayawayKeepMemory"]; second.launch()
        XCTAssertTrue(second.tables["song-table"].waitForExistence(timeout: 8), "the playlist that was open is open again")
        let controller = second.descendants(matching: .any)["floating-controller"]
        XCTAssertTrue(controller.waitForExistence(timeout: 5), "the song that was playing is shown")
        XCTAssertTrue(second.buttons["Play"].exists, "it comes back paused, not playing")
        controller.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        XCTAssertTrue(second.descendants(matching: .any)["player-card"].waitForExistence(timeout: 3))
        XCTAssertTrue(second.staticTexts["Demo Two"].exists, "the same song")
        let savedPlace = second.staticTexts.matching(NSPredicate(format: "label MATCHES '0:0[3-9]'"))
        XCTAssertGreaterThan(savedPlace.count, 0, "the place in the song is remembered")
        second.buttons["Play"].firstMatch.tap()
        XCTAssertTrue(second.buttons["Pause"].waitForExistence(timeout: 3), "Play carries on from the remembered song")
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
