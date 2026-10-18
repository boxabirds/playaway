import XCTest
@testable import LocalPlayer
@testable import PlayawayCore

/// Story 42, mac.question_ui: a song added on an iPhone from a place the Mac cannot reach shows the question-mark cloud,
/// says what to do when clicked, and reads 'on another device' to a script. The window and the script read the same
/// answer; a file deleted on this Mac stays as it was.
@MainActor
final class ElsewhereMacTests: XCTestCase {
    let dir = TempDir("elsewhere")
    var app: TestApp!
    override func tearDown() async throws { app?.tearDown() }

    func open() throws -> (doc: PlaylistDocument, window: PlaylistWindowController, tracks: [Track], folder: URL) {
        let root = dir.url.appendingPathComponent("Cloud", isDirectory: true)
        let folder = root.appendingPathComponent("Trip", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let here = folder.appendingPathComponent("here.mp3")
        try FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: here)
        app = TestApp(cloudRoot: { root })
        app.services.cloud.isUbiquitous = CloudStandIn.isUbiquitous(for: .folder(root))!
        let tracks = [
            Track(id: UUID(), reference: TrackReference.make(for: here)!),
            // Added on an iPhone from its own container: a dead bookmark, an iOS path, no place in iCloud.
            Track(id: UUID(), reference: TrackReference(bookmark: Data([0]), lastKnownPath: "/private/var/mobile/Containers/Data/Application/AAAA/Documents/phone.mp3", fileName: "phone.mp3")),
            // Deleted on this Mac: a Mac path inside this Mac's home that is gone.
            Track(id: UUID(), reference: TrackReference(bookmark: Data([0]), lastKnownPath: NSHomeDirectory() + "/Music/deleted-here.mp3", fileName: "deleted-here.mp3")),
        ]
        let doc = app.openSaved(Playlist(tracks: tracks), at: folder.appendingPathComponent("Trip.\(playlistFileExtension)"))
        var done = false; doc.resolveStatuses { done = true }; spin { done }
        let window = app.window(of: doc)
        window.reload()
        return (doc, window, tracks, folder)
    }

    func cell(_ window: PlaylistWindowController, _ row: Int) -> TrackCellView {
        window.tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as! TrackCellView
    }

    func testTheRowShowsTheQuestionCloudAndAClickSaysWhatToDo() throws {            // TC-20, TC-21
        let (_, window, tracks, _) = try open()
        XCTAssertEqual(cell(window, 1).cloudKind, .elsewhere, "an iPhone-made song the Mac cannot reach")
        XCTAssertEqual(cell(window, 0).cloudKind, .outline, "a song that is here keeps its cloud")
        window.cloudIconClicked(tracks[1])
        XCTAssertEqual(app.notices.shown, [.addedElsewhere])
        XCTAssertEqual(app.notices.shown.first?.detail, addedElsewhereMessage)
        XCTAssertNil(app.services.engine.currentURL, "a click never plays the song")
    }

    func testTheScriptReadsOnAnotherDeviceForTheSameSong() throws {                 // TC-22, TC-24
        let (doc, window, _, _) = try open()
        let actions = AppActions(services: app.services); actions.isReady = { true }
        let states = try actions.trackICloudStates("Trip")
        XCTAssertEqual(states[1], "on another device")
        XCTAssertEqual(doc.scriptTrackICloudStates, states)
        for (row, state) in states.enumerated() {
            XCTAssertEqual(cell(window, row).cloudKind == .elsewhere, state == "on another device", "row \(row): the window and the script agree")
        }
    }

    func testAFileDeletedOnThisMacKeepsItsOldBehaviour() throws {                   // TC-23
        let (doc, window, tracks, _) = try open()
        XCTAssertNil(cell(window, 2).cloudKind, "no cloud for a song that was here and is gone")
        XCTAssertEqual(doc.unfoundKind(of: tracks[2]), .gone)
        let actions = AppActions(services: app.services); actions.isReady = { true }
        XCTAssertEqual(try actions.trackICloudStates("Trip")[2], "not in iCloud", "unchanged")
        window.cloudIconClicked(tracks[2])
        XCTAssertEqual(app.notices.shown, [], "no new message for it")
    }

    func testTheCloudBecomesOrdinaryWhenTheSongArrives() throws {                   // state transition
        let (doc, window, tracks, folder) = try open()
        XCTAssertEqual(cell(window, 1).cloudKind, .elsewhere)
        let arrived = folder.appendingPathComponent("phone.mp3")
        try FileManager.default.copyItem(at: Fixtures.url("track2.mp3"), to: arrived)
        var updated = doc.playlist
        updated.tracks[1] = Track(id: tracks[1].id, reference: TrackReference.make(for: arrived)!)
        doc.acceptTransferred(updated)
        var done = false; doc.resolveStatuses { done = true }; spin { done }
        window.reload()
        XCTAssertEqual(cell(window, 1).cloudKind, .outline, "found here now: the ordinary cloud")
    }
}
