import XCTest
import AppKit
@testable import LocalPlayer
@testable import PlayawayCore

/// Story 21 on the Mac: songs dropped (or added by the menu) into a synced playlist go through the one shared Files
/// flow of story 19: added where they are with the outline cloud when already in iCloud, otherwise the one Files
/// question for the dropped songs, then Move, Copy or Add Without Syncing with the same report and the rows following
/// the files. An unsynced playlist takes a drop as it always did. A temp folder stands in for the Playaway folder;
/// real iCloud and a real drag are not exercised.
@MainActor
final class DropIntakeTests: XCTestCase {
    var app: TestApp!
    let cloud = TempDir("dropcloud")
    let docs = TempDir("dropdocs")
    private var fixtures: [PlaylistFixture] = []

    override func setUp() async throws {
        let root = cloud.url
        app = TestApp(cloudRoot: { root })
    }
    override func tearDown() async throws { app.tearDown() }

    /// A synced playlist (its file inside the stand-in folder) with the given songs already in its folder.
    private func openSynced(_ name: String = "Dinner", songs: [String] = []) -> PlaylistDocument {
        let folder = cloud.url.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tracks = songs.map { song -> Track in
            let url = folder.appendingPathComponent(song)
            try! FileManager.default.copyItem(at: Fixtures.url(song), to: url)
            return Track(id: UUID(), reference: TrackReference.make(for: url)!)
        }
        return app.openSaved(Playlist(tracks: tracks), at: folder.appendingPathComponent("\(name).\(playlistFileExtension)"))
    }

    /// Songs outside iCloud, in their own temp folder.
    private func outside(_ names: [String]) -> PlaylistFixture {
        let fixture = PlaylistFixture(trackNames: names)
        fixtures.append(fixture)
        return fixture
    }

    private func drop(_ urls: [URL], into doc: PlaylistDocument, answer: FilesChoice? = nil) -> PlaylistWindowController {
        let window = app.window(of: doc)
        if let answer { window.askFilesChoice = { answer } }
        window.dropFiles(urls)
        spin { window.intakeFinished }
        window.reload()
        return window
    }

    private func paths(_ doc: PlaylistDocument) -> [String] { doc.playlist.tracks.map { URL(fileURLWithPath: $0.reference.lastKnownPath).canonicalPath } }
    private func inCloud(_ name: String, playlist: String = "Dinner") -> String { cloud.url.appendingPathComponent(playlist).appendingPathComponent(name).canonicalPath }
    private func cell(_ doc: PlaylistDocument, _ row: Int) -> TrackCellView {
        app.window(of: doc).tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as! TrackCellView
    }

    // MARK: The gate (TC-01, TC-02, TC-12, TC-13, TC-32, TC-33, TC-34)

    func testADropIntoAnUnsyncedPlaylistAddsTheRowsAsTodayAndAsksNothing() {
        let fixture = outside(["track1.mp3", "track2.mp3"])
        let doc = app.openSaved(Playlist(), at: docs.path("Local.\(playlistFileExtension)"))
        let window = drop(fixture.urls, into: doc, answer: .moveToICloud)
        XCTAssertEqual(window.filesAsked, 0, "no question")
        XCTAssertEqual(paths(doc), fixture.urls.map(\.canonicalPath), "rows at the dropped files")
        XCTAssertNil(cell(doc, 0).cloudKind, "no cloud state on an unsynced playlist")
        for url in fixture.urls { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) }
    }

    func testDroppedSongsAlreadyInICloudAreAddedWithTheOutlineCloudAndNoQuestion() {
        let doc = openSynced()
        let inside = ["track1.mp3", "track2.mp3"].map { name -> URL in
            let url = cloud.url.appendingPathComponent("Elsewhere/\(name)")
            try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! FileManager.default.copyItem(at: Fixtures.url(name), to: url)
            return url
        }
        let window = drop(inside, into: doc, answer: .moveToICloud)
        XCTAssertEqual(window.filesAsked, 0, "all in iCloud: nothing to ask")
        XCTAssertEqual(paths(doc), inside.map(\.canonicalPath), "added where they are, not moved into this playlist's folder")
        XCTAssertEqual(cell(doc, 0).cloudKind, .outline)
        XCTAssertEqual(cell(doc, 1).cloudKind, .outline)
        XCTAssertFalse(cell(doc, 0).isGreyedOut)
    }

    func testADropOfNothingSupportedChangesNothingAndAsksNothing() {
        let doc = openSynced(songs: ["track1.mp3"])
        let text = docs.path("notes.txt")
        try! Data("hello".utf8).write(to: text)
        let window = drop([text], into: doc, answer: .moveToICloud)
        XCTAssertEqual(window.filesAsked, 0)
        XCTAssertEqual(doc.playlist.tracks.count, 1, "rejected as today")
    }

    func testOneQuestionPerDropNotPerSongAndNothingMovesBeforeTheAnswer() {
        let fixture = outside(["track1.mp3", "track2.mp3", "track3.mp3"])
        let doc = openSynced()
        let window = app.window(of: doc)
        var asked = 0
        window.askFilesChoice = {
            asked += 1
            for url in fixture.urls { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "untouched while the question is open") }
            XCTAssertFalse(FileManager.default.fileExists(atPath: self.cloud.url.appendingPathComponent("Dinner/track1.mp3").path))
            return .moveToICloud
        }
        window.dropFiles(fixture.urls)
        spin { window.intakeFinished }
        XCTAssertEqual(asked, 1, "one question for the three songs")
    }

    // MARK: Apply (TC-03, TC-04, TC-06, TC-07, TC-10, TC-17, TC-18, TC-22, TC-31, TC-35)

    func testMoveToICloudMovesTheDroppedSongsBesideThePlaylistAndTheRowsFollowAfterTheExistingOnes() {
        let doc = openSynced(songs: ["tone.wav"])
        let existing = paths(doc)
        let fixture = outside(["track1.mp3", "track2.mp3"])
        let window = drop(fixture.urls, into: doc, answer: .moveToICloud)
        XCTAssertEqual(window.filesAsked, 1)
        XCTAssertEqual(paths(doc), existing + [inCloud("track1.mp3"), inCloud("track2.mp3")], "existing row first, dropped rows after, in dropped order")
        for url in fixture.urls { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "moved, not copied") }
        XCTAssertEqual(cell(doc, 1).cloudKind, .outline); XCTAssertEqual(cell(doc, 2).cloudKind, .outline)
        XCTAssertEqual(window.filesMessages, [])
        XCTAssertEqual(doc.sync.state, .on)
    }

    func testCopyToICloudCopiesTheDroppedSongsAndKeepsTheOriginals() {
        let doc = openSynced()
        let fixture = outside(["track1.mp3", "track2.mp3"])
        let window = drop(fixture.urls, into: doc, answer: .copyToICloud)
        XCTAssertEqual(paths(doc), [inCloud("track1.mp3"), inCloud("track2.mp3")], "the rows play the copies")
        for url in fixture.urls { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the original stays") }
        XCTAssertEqual(window.filesMessages, [])
        XCTAssertEqual(cell(doc, 0).cloudKind, .outline)
    }

    func testAMixedDropMovesOnlyTheSongsNotInICloudAndKeepsTheDroppedOrder() {
        let doc = openSynced()
        let inside = cloud.url.appendingPathComponent("Elsewhere/track2.mp3")
        try! FileManager.default.createDirectory(at: inside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! FileManager.default.copyItem(at: Fixtures.url("track2.mp3"), to: inside)
        let fixture = outside(["track1.mp3", "track3.mp3"])
        let dropped = [fixture.urls[0], inside, fixture.urls[1]]
        let window = drop(dropped, into: doc, answer: .moveToICloud)
        XCTAssertEqual(window.filesAsked, 1)
        XCTAssertEqual(paths(doc), [inCloud("track1.mp3"), inside.canonicalPath, inCloud("track3.mp3")], "the in-iCloud song is untouched, order kept")
        XCTAssertTrue(FileManager.default.fileExists(atPath: inside.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.url.appendingPathComponent("Dinner/track2.mp3").path), "never duplicated")
    }

    func testAReadOnlyDroppedSongIsCopiedInsteadAndTheReportSaysOne() throws {
        let doc = openSynced()
        let fixture = outside(["track1.mp3"])
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.dir.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.dir.url.path) }
        let window = drop(fixture.urls, into: doc, answer: .moveToICloud)
        XCTAssertEqual(paths(doc), [inCloud("track1.mp3")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.urls[0].path), "the original stays")
        XCTAssertEqual(window.filesMessages, [FilesPrompt.copiedInsteadReport(1)!], "the one shared report wording")
    }

    func testADroppedSongThatCannotBeMovedIsNamedAndAddedWhereItIsWhileTheOthersAreHandled() throws {
        let doc = openSynced(songs: ["track1.mp3"])                             // the same name is already beside the playlist
        let fixture = outside(["track1.mp3", "track2.mp3"])
        let bytes = try Data(contentsOf: fixture.urls[0])
        let window = drop(fixture.urls, into: doc, answer: .moveToICloud)
        XCTAssertEqual(paths(doc), [inCloud("track1.mp3"), fixture.urls[0].canonicalPath, inCloud("track2.mp3")])
        XCTAssertEqual(try Data(contentsOf: fixture.urls[0]), bytes, "the failed song's file is intact")
        XCTAssertEqual(cell(doc, 1).cloudKind, .crossedOut); XCTAssertFalse(cell(doc, 1).isGreyedOut)
        XCTAssertEqual(window.filesMessages.count, 1)
        XCTAssertTrue(window.filesMessages[0].contains("track1.mp3"), window.filesMessages[0])
    }

    // MARK: Add Without Syncing (TC-05, TC-08, TC-80 to TC-84, TC-87, TC-88)

    func testAddWithoutSyncingAddsTheDroppedSongsWhereTheyAreCrossedOutNotDimmedAndPlayable() {
        let doc = openSynced(songs: ["tone.wav"])
        let existing = paths(doc)
        let fixture = outside(["track1.mp3", "track2.mp3"])
        let window = drop(fixture.urls, into: doc, answer: .doNothing)
        XCTAssertEqual(window.filesAsked, 1)
        XCTAssertEqual(paths(doc), existing + fixture.urls.map(\.canonicalPath), "added where they are, in dropped order, after the existing rows")
        for url in fixture.urls { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.url.appendingPathComponent("Dinner/track1.mp3").path), "nothing copied")
        XCTAssertEqual(doc.sync.state, .on, "sync stays on")
        XCTAssertEqual(cell(doc, 1).cloudKind, .crossedOut); XCTAssertFalse(cell(doc, 1).isGreyedOut)
        XCTAssertEqual(cell(doc, 2).cloudKind, .crossedOut); XCTAssertFalse(cell(doc, 2).isGreyedOut)
        XCTAssertEqual(cell(doc, 0).cloudKind, .outline, "the existing song is unchanged")
        window.playRow(1)
        XCTAssertEqual(app.services.engine.currentURL, fixture.urls[0], "it plays from where it is")
    }

    func testAddWithoutSyncingOnAMixedDropKeepsTheOrderAndEachSongsOwnCloud() {
        let doc = openSynced()
        let inside = cloud.url.appendingPathComponent("Elsewhere/track2.mp3")
        try! FileManager.default.createDirectory(at: inside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! FileManager.default.copyItem(at: Fixtures.url("track2.mp3"), to: inside)
        let fixture = outside(["track1.mp3", "track3.mp3"])
        let dropped = [fixture.urls[0], inside, fixture.urls[1]]
        _ = drop(dropped, into: doc, answer: .doNothing)
        XCTAssertEqual(paths(doc), dropped.map(\.canonicalPath))
        XCTAssertEqual([cell(doc, 0).cloudKind, cell(doc, 1).cloudKind, cell(doc, 2).cloudKind], [.crossedOut, .outline, .crossedOut])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.url.appendingPathComponent("Dinner/track1.mp3").path))
    }

    func testDismissingTheQuestionOnADropIsAddWithoutSyncing() {
        let doc = openSynced()
        let fixture = outside(["track1.mp3"])
        let window = app.window(of: doc)
        window.askFilesChoice = { .doNothing }                                 // the sheet's escape maps to this answer (story 19)
        window.dropFiles(fixture.urls)
        spin { window.intakeFinished }
        XCTAssertEqual(paths(doc), [fixture.urls[0].canonicalPath])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.urls[0].path))
    }

    // MARK: The same flow for every entry (TC-90 to TC-93, TC-99, TC-100, TC-101)

    func testAddFilesByMenuGoesThroughTheSameFlowAsADrop() {
        let doc = openSynced()
        let fixture = outside(["track1.mp3"])
        let window = app.window(of: doc)
        window.askFilesChoice = { .copyToICloud }
        window.chooseFilesToAdd = { fixture.urls }
        window.addFiles(nil)
        spin { window.intakeFinished }
        XCTAssertEqual(window.filesAsked, 1)
        XCTAssertEqual(paths(doc), [inCloud("track1.mp3")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.urls[0].path))
    }

    func testADropAndTurningSyncOnGiveTheSameOutcomeForTheSameSongs() {
        for answer in [FilesChoice.moveToICloud, .copyToICloud, .doNothing] {
            // By drop: a synced playlist takes the songs.
            let byDrop = openSynced("Drop-\(answer)")
            let dropped = outside(["track1.mp3", "track2.mp3"])
            let dropWindow = drop(dropped.urls, into: byDrop, answer: answer)
            // By the main flow: a playlist outside iCloud with the same songs is synced.
            let turned = outside(["track1.mp3", "track2.mp3"])
            let byTurnOn = app.openSaved(turned.playlist, at: docs.path("TurnOn-\(answer).\(playlistFileExtension)"))
            let turnWindow = app.window(of: byTurnOn)
            turnWindow.askPlaylistChoice = { .move }
            turnWindow.askFilesChoice = { answer }
            turnWindow.syncPressed(nil)
            spin { turnWindow.intakeFinished }
            turnWindow.reload()
            // Same question count, same messages, same layout relative to each playlist's folder, same icons.
            XCTAssertEqual(dropWindow.filesAsked, turnWindow.filesAsked, "\(answer)")
            XCTAssertEqual(dropWindow.filesMessages, turnWindow.filesMessages, "\(answer)")
            let relative = { (doc: PlaylistDocument) -> [String] in
                doc.playlist.tracks.map { track in
                    let path = URL(fileURLWithPath: track.reference.lastKnownPath).canonicalPath
                    return path.hasPrefix(doc.folder!.canonicalPath) ? "folder/" + track.reference.fileName : "outside/" + track.reference.fileName
                }
            }
            XCTAssertEqual(relative(byDrop), relative(byTurnOn), "\(answer)")
            XCTAssertEqual([cell(byDrop, 0).cloudKind, cell(byDrop, 1).cloudKind], [cell(byTurnOn, 0).cloudKind, cell(byTurnOn, 1).cloudKind], "\(answer)")
            XCTAssertEqual(dropped.urls.map { FileManager.default.fileExists(atPath: $0.path) }, turned.urls.map { FileManager.default.fileExists(atPath: $0.path) }, "\(answer): originals kept or moved alike")
        }
    }
}
