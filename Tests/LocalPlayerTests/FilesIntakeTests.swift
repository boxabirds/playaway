import XCTest
import AppKit
@testable import LocalPlayer
@testable import PlayawayCore

/// Story 19 on the Mac: once a playlist has been moved into iCloud, the songs that are not in iCloud are offered the
/// Files question through the one shared flow; the answer moves, copies or leaves them, the rows follow, and the
/// report and failure messages reach the person. A temp folder stands in for the Playaway folder and "in iCloud"
/// means strictly inside it; real iCloud is not exercised.
@MainActor
final class FilesIntakeTests: XCTestCase {
    var app: TestApp!
    let docs = TempDir("intakedocs")
    let cloud = TempDir("intakecloud")
    private var fixtures: [PlaylistFixture] = []

    override func setUp() async throws {
        let root = cloud.url
        app = TestApp(cloudRoot: { root })
    }
    override func tearDown() async throws { app.tearDown() }

    /// A saved playlist outside iCloud whose songs are in their own folder, also outside iCloud.
    private func open(_ name: String, songs: [String] = ["track1.mp3", "track2.mp3"]) -> (PlaylistDocument, PlaylistFixture) {
        let fixture = PlaylistFixture(trackNames: songs)
        fixtures.append(fixture)
        return (app.openSaved(fixture.playlist, at: docs.path("\(name).\(playlistFileExtension)")), fixture)
    }

    private func sync(_ doc: PlaylistDocument, files answer: FilesChoice) -> PlaylistWindowController {
        let window = app.window(of: doc)
        window.askPlaylistChoice = { .move }
        window.askFilesChoice = { answer }
        window.syncPressed(nil)
        return window
    }

    private func settled(_ doc: PlaylistDocument, _ window: PlaylistWindowController) {
        spin { window.filesAsked >= 1 && window.intakeFinished }
    }

    private func names(_ doc: PlaylistDocument) -> [String] { doc.playlist.tracks.map(\.reference.fileName) }
    private func paths(_ doc: PlaylistDocument) -> [String] { doc.playlist.tracks.map { URL(fileURLWithPath: $0.reference.lastKnownPath).canonicalPath } }
    private func inCloud(_ name: String, playlist: String = "Morning") -> String { cloud.url.appendingPathComponent(playlist).appendingPathComponent(name).canonicalPath }

    func testMoveToICloudMovesTheSongsBesideThePlaylistAndTheRowsFollow() throws {              // TC-03, TC-25, TC-113, TC-17
        let (doc, fixture) = open("Morning")
        let idsBefore = doc.playlist.tracks.map(\.id), namesBefore = names(doc)
        let window = sync(doc, files: .moveToICloud)
        settled(doc, window)
        XCTAssertEqual(window.filesAsked, 1, "asked once")
        XCTAssertEqual(paths(doc), namesBefore.map { inCloud($0) })
        XCTAssertEqual(doc.playlist.tracks.map(\.id), idsBefore, "same rows, same order")
        XCTAssertEqual(names(doc), namesBefore)
        for url in fixture.urls { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "moved, not copied") }
        XCTAssertEqual(window.filesMessages, [], "no report when everything moved")
        var done = false; doc.resolveStatuses { done = true }; spin { done }
        XCTAssertTrue(doc.playlist.tracks.allSatisfy { doc.statuses.status(of: $0.id) != .missing }, "every row plays from its new place")
        XCTAssertEqual(doc.sync.state, .on)
    }

    func testCopyToICloudKeepsTheOriginalsAndTheRowsPlayTheCopies() throws {                     // TC-04, TC-33
        let (doc, fixture) = open("Morning")
        let window = sync(doc, files: .copyToICloud)
        settled(doc, window)
        XCTAssertEqual(paths(doc), names(doc).map { inCloud($0) })
        for url in fixture.urls { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the original stays") }
        XCTAssertEqual(window.filesMessages, [], "no report after Copy")
    }

    func testAddWithoutSyncingLeavesEverySongWhereItIsWithSyncOn() throws {                      // TC-05, TC-70, TC-74, TC-76
        let (doc, fixture) = open("Morning")
        let before = paths(doc)
        let window = sync(doc, files: .doNothing)
        settled(doc, window)
        XCTAssertEqual(paths(doc), before)
        for url in fixture.urls { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.url.appendingPathComponent("Morning/track1.mp3").path), "nothing copied")
        XCTAssertEqual(doc.sync.state, .on, "sync stays on")
        var done = false; doc.resolveStatuses { done = true }; spin { done }
        XCTAssertTrue(doc.playlist.tracks.allSatisfy { doc.statuses.status(of: $0.id) != .missing }, "still playable from where they are")
        XCTAssertEqual(window.filesMessages, [])
    }

    func testDismissingTheFilesQuestionIsAddWithoutSyncing() throws {                             // TC-19, TC-72
        let (doc, fixture) = open("Morning")
        let before = paths(doc)
        let window = sync(doc, files: FilesPrompt.dismissalChoice)
        settled(doc, window)
        XCTAssertEqual(paths(doc), before)
        for url in fixture.urls { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) }
    }

    func testSongsAlreadyInICloudAreNotAskedAboutOrTouched() throws {                            // TC-01, TC-12, TC-32, TC-112
        let folder = cloud.url.appendingPathComponent("Music")           // elsewhere in iCloud: already in, not asked about
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var tracks: [Track] = []
        for name in ["track1.mp3", "track2.mp3"] {
            let url = folder.appendingPathComponent(name)
            try FileManager.default.copyItem(at: Fixtures.url(name), to: url)
            tracks.append(Track(id: UUID(), reference: TrackReference.make(for: url)!))
        }
        let doc = app.openSaved(Playlist(tracks: tracks), at: docs.path("Morning.\(playlistFileExtension)"))
        let before = paths(doc)
        let window = sync(doc, files: .moveToICloud)
        spin { doc.sync.state == .on && window.intakeFinished }
        XCTAssertEqual(window.filesAsked, 0, "nothing to move: no question")
        XCTAssertEqual(paths(doc), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(), ["track1.mp3", "track2.mp3"], "untouched")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cloud.url.appendingPathComponent("Morning").path), ["Morning.\(playlistFileExtension)"], "only the playlist moved")
    }

    func testReadOnlySongsAreCopiedInsteadAndTheReportSaysHowMany() throws {                     // TC-06, TC-18
        let (doc, fixture) = open("Morning")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.dir.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.dir.url.path) }
        let window = sync(doc, files: .moveToICloud)
        settled(doc, window)
        XCTAssertEqual(paths(doc), names(doc).map { inCloud($0) }, "the rows play the copies")
        for url in fixture.urls { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the original stays") }
        XCTAssertEqual(window.filesMessages, ["2 files were on separate volumes or read only and copies were placed on iCloud, NOT moved"])
    }

    func testASongThatCannotBeMovedIsNamedAndTheOthersAreStillHandled() throws {                 // TC-21, TC-24, TC-30, TC-115
        // Two songs with the same file name from different folders: the second cannot land beside the first.
        let first = PlaylistFixture(trackNames: ["track1.mp3"]), second = PlaylistFixture(trackNames: ["track1.mp3"])
        fixtures += [first, second]
        let doc = app.openSaved(Playlist(tracks: first.tracks + second.tracks), at: docs.path("Morning.\(playlistFileExtension)"))
        let secondBytes = try Data(contentsOf: second.urls[0])
        let window = sync(doc, files: .moveToICloud)
        settled(doc, window)
        XCTAssertEqual(paths(doc)[0], inCloud("track1.mp3"), "the first song moved")
        XCTAssertEqual(paths(doc)[1], second.urls[0].canonicalPath, "the failed song's row is unchanged")
        XCTAssertEqual(try Data(contentsOf: second.urls[0]), secondBytes, "and its file is intact")
        XCTAssertEqual(try Data(contentsOf: cloud.url.appendingPathComponent("Morning/track1.mp3")), try Data(contentsOf: Fixtures.url("track1.mp3")), "nothing overwritten")
        XCTAssertEqual(window.filesMessages.count, 1)
        XCTAssertTrue(window.filesMessages.first?.contains("track1.mp3") ?? false, "\(window.filesMessages)")
    }

    func testTheScriptRouteSuppliesBothAnswersAndGivesTheSameFiles() throws {                   // story 22's shape, proven here for parity
        let (doc, fixture) = open("Morning")
        let actions = AppActions(services: app.services)
        actions.isReady = { true }
        let path = try actions.syncPlaylist("Morning", answering: "move", files: "copy")
        XCTAssertEqual(URL(fileURLWithPath: path).canonicalPath, inCloud("Morning.\(playlistFileExtension)"))
        XCTAssertEqual(paths(doc), names(doc).map { inCloud($0) })
        for url in fixture.urls { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) }
    }

    func testTheScriptRouteWithoutAFilesAnswerAddsWithoutSyncing() throws {
        let (doc, fixture) = open("Morning")
        let before = paths(doc)
        let actions = AppActions(services: app.services)
        actions.isReady = { true }
        _ = try actions.syncPlaylist("Morning", answering: "move", files: nil)
        XCTAssertEqual(doc.sync.state, .on)
        XCTAssertEqual(paths(doc), before, "no answer for the Files question: songs are added without syncing")
        for url in fixture.urls { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) }
    }

    func testThePlaylistIsNotAskedWhenItIsNotAnICloudPlaylist() throws {                          // TC-34
        let (doc, _) = open("Morning")
        let window = app.window(of: doc)
        window.askPlaylistChoice = { .dontSync }
        window.askFilesChoice = { .moveToICloud }
        window.syncPressed(nil)
        spin(timeout: 0.5) { false }
        XCTAssertEqual(window.filesAsked, 0, "a playlist left outside iCloud is never asked about its songs")
    }
}
