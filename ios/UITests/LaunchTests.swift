import XCTest

@MainActor final class LaunchTests: XCTestCase {
    func testAppLaunchesToThePlaylistsScreen() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.navigationBars["Playlists"].waitForExistence(timeout: 5))
    }
}
