import XCTest
import AppKit
@testable import LocalPlayer
@testable import PlayawayCore

/// Story 18 on the Mac: the title-bar cloud button of a playlist window turns iCloud sync on through the shared core,
/// with the Playaway folder stood in by a temp folder. Real documents, real windows (not shown), real file moves.
@MainActor
final class PlaylistSyncControllerTests: XCTestCase {
    var app: TestApp!
    let docs = TempDir("syncdocs")
    let cloud = TempDir("synccloud")
    var rootAvailable = true

    override func setUp() async throws {
        app = TestApp(cloudRoot: { [self] in rootAvailable ? cloud.url : nil })
    }
    override func tearDown() async throws { app.tearDown() }

    private func open(_ name: String, in folder: URL? = nil) -> PlaylistDocument {
        let fixture = PlaylistFixture(trackNames: ["track1.mp3", "track2.mp3"])
        fixtures.append(fixture)
        let url = (folder ?? docs.url).appendingPathComponent("\(name).\(playlistFileExtension)")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return app.openSaved(fixture.playlist, at: url)
    }
    private var fixtures: [PlaylistFixture] = []

    private func press(_ window: PlaylistWindowController, answering answer: PlaylistChoice) {
        window.askPlaylistChoice = { answer }
        window.syncPressed(nil)
    }

    func testThePlaylistWindowShowsTheSwitchOffForAPlaylistOutsideICloud() {                  // TC-01 (look), TC-18
        let doc = open("Morning")
        let window = app.window(of: doc)
        XCTAssertEqual(window.syncButton.accessibilityIdentifier(), ElementID.sync)
        XCTAssertEqual(window.syncButton.accessibilityLabel(), "iCloud sync for this playlist")
        XCTAssertEqual(window.syncButton.accessibilityValue() as? String, "off")
        XCTAssertEqual(window.syncSymbolName, "icloud.slash")
        XCTAssertTrue(window.syncButton.isEnabled)
        XCTAssertTrue(window.window!.titlebarAccessoryViewControllers.contains { $0.view.subviews.contains(window.syncButton) || $0.view === window.syncButton },
                      "the switch sits in the title bar")
        XCTAssertEqual(doc.sync.state, .off)
    }

    func testMoveMovesThePlaylistIntoItsOwnFolderInICloudAndTheWindowFollows() throws {        // TC-02, TC-07, TC-22
        let doc = open("Morning")
        let window = app.window(of: doc)
        let audioBefore = try FileManager.default.contentsOfDirectory(atPath: fixtures[0].dir.url.path).sorted()
        press(window, answering: .move)
        spin { window.syncButton.accessibilityValue() as? String == "on" }   // what the person sees, after the move
        let expected = cloud.url.appendingPathComponent("Morning").appendingPathComponent("Morning.\(playlistFileExtension)")
        XCTAssertEqual(doc.fileURL?.canonicalPath, expected.canonicalPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: docs.path("Morning.\(playlistFileExtension)").path), "moved, not copied")
        XCTAssertEqual(doc.displayName, "Morning")
        XCTAssertEqual(doc.playlist.tracks.count, 2, "the open playlist is the same playlist")
        XCTAssertEqual(window.syncButton.accessibilityValue() as? String, "on")
        XCTAssertEqual(window.syncSymbolName, "icloud.fill")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixtures[0].dir.url.path).sorted(), audioBefore, "no audio file is touched")
        XCTAssertTrue(app.notices.shown.isEmpty)
    }

    func testDontSyncLeavesThePlaylistWhereItIsWithTheSwitchOff() {                              // TC-03, TC-08, TC-20
        let doc = open("Morning")
        let window = app.window(of: doc)
        let before = doc.fileURL
        press(window, answering: .dontSync)
        spin(timeout: 0.5) { false }
        XCTAssertEqual(doc.fileURL, before)
        XCTAssertEqual(doc.sync.state, .off)
        XCTAssertEqual(window.syncButton.accessibilityValue() as? String, "off")
        XCTAssertEqual(try? FileManager.default.contentsOfDirectory(atPath: cloud.url.path), [], "nothing created in iCloud")
    }

    func testAPlaylistAlreadyInThePlayawayFolderIsOnAndThePressDoesNothing() {                  // TC-05, TC-06, TC-23
        let doc = open("Morning", in: cloud.url.appendingPathComponent("Morning"))
        let window = app.window(of: doc)
        XCTAssertEqual(doc.sync.state, .on)
        XCTAssertEqual(window.syncButton.accessibilityValue() as? String, "on")
        var asked = 0
        window.askPlaylistChoice = { asked += 1; return .move }
        let before = doc.fileURL
        window.syncPressed(nil)
        spin(timeout: 0.5) { false }
        XCTAssertEqual(asked, 0, "no dialog")
        XCTAssertEqual(doc.fileURL, before)
        XCTAssertEqual(doc.sync.state, .on)
    }

    func testAFailedMoveLeavesEverythingAndSaysSo() throws {                                     // TC-10, TC-21
        let doc = open("Morning")
        let window = app.window(of: doc)
        let before = doc.fileURL!
        let bytes = try Data(contentsOf: before)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: cloud.url.path)   // cannot be written
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cloud.url.path) }
        press(window, answering: .move)
        spin { !app.notices.shown.isEmpty }
        XCTAssertEqual(doc.fileURL, before)
        XCTAssertEqual(try Data(contentsOf: before), bytes)
        XCTAssertEqual(doc.sync.state, .off)
        XCTAssertEqual(window.syncButton.accessibilityValue() as? String, "off")
        XCTAssertFalse(app.notices.shown.isEmpty, "the person is told it could not be moved")
    }

    func testTheStateIsRememberedWhenThePlaylistIsReopened() {                                   // TC-15
        let doc = open("Morning")
        press(app.window(of: doc), answering: .move)
        spin { doc.sync.state == .on }
        let url = doc.fileURL!
        doc.close()
        var opened: NSDocument?; var done = false
        app.controller.openDocument(withContentsOf: url, display: true) { document, _, _ in opened = document; done = true }
        spin { done }
        let again = opened as! PlaylistDocument
        XCTAssertEqual(again.sync.state, .on)
        XCTAssertEqual(app.window(of: again).syncButton.accessibilityValue() as? String, "on")
    }

    func testTurningOnOnePlaylistLeavesOtherOpenPlaylistsAlone() {                                // TC-24
        let morning = open("Morning")
        let evening = open("Evening")
        press(app.window(of: morning), answering: .move)
        spin { morning.sync.state == .on }
        XCTAssertEqual(evening.sync.state, .off)
        XCTAssertEqual(evening.fileURL?.path, docs.path("Evening.\(playlistFileExtension)").path)
    }

    func testWhileICloudIsUnavailableTheSwitchIsDisabledWithAReasonAndAPressDoesNothing() {      // TC-30, TC-31, TC-37, TC-38
        rootAvailable = false
        app.services.cloud.refresh()
        let outside = open("Morning")
        let inside = open("Evening", in: cloud.url.appendingPathComponent("Evening"))
        // With no reachable Playaway folder, whether a file is inside it cannot be known: every switch reads off,
        // disabled, with the reason (open question 11 decided here: the state is the file's location, not a stored flag).
        for doc in [outside, inside] {
            let window = app.window(of: doc)
            XCTAssertFalse(window.syncButton.isEnabled)
            XCTAssertEqual(window.syncButton.toolTip, ICloudAvailability.unavailableReason)
            XCTAssertEqual(window.syncReason.stringValue, ICloudAvailability.unavailableReason, "the reason is visible")
            XCTAssertFalse(window.syncReason.isHidden)
            XCTAssertTrue((window.syncButton.accessibilityValue() as? String ?? "").contains(ICloudAvailability.unavailableReason))
        }
        var asked = 0
        let window = app.window(of: outside)
        window.askPlaylistChoice = { asked += 1; return .move }
        let before = outside.fileURL
        window.syncPressed(nil)
        spin(timeout: 0.5) { false }
        XCTAssertEqual(asked, 0)
        XCTAssertEqual(outside.fileURL, before)
        XCTAssertEqual(outside.sync.state, .off)
    }

    func testTheSwitchComesBackWhenICloudBecomesAvailable() {                                     // TC-32
        rootAvailable = false
        app.services.cloud.refresh()
        let doc = open("Morning")
        let window = app.window(of: doc)
        XCTAssertFalse(window.syncButton.isEnabled)
        rootAvailable = true
        app.services.cloud.refresh()
        spin(timeout: 1) { window.syncButton.isEnabled }
        XCTAssertTrue(window.syncButton.isEnabled)
        XCTAssertTrue(window.syncReason.isHidden)
        var asked = 0
        window.askPlaylistChoice = { asked += 1; return .dontSync }
        window.syncPressed(nil)
        spin(timeout: 1) { asked == 1 }
        XCTAssertEqual(asked, 1, "a press now asks")
    }
}
