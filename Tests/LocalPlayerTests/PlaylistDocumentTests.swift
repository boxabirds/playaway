import XCTest
import AppKit
@testable import LocalPlayer

@MainActor
final class PlaylistDocumentTests: XCTestCase {
    var app: TestApp!
    let dir = TempDir("docs")
    let audio = TempDir("audio")

    override func setUp() async throws { app = TestApp() }
    override func tearDown() async throws { app.tearDown() }

    func files(_ names: [String]) -> [URL] { names.map { audio.copyFixture($0) } }

    // MARK: lifecycle (TC-40..TC-52 of story 4)

    func testNewPlaylistIsUntitledEmptyWithOneWindowAndNoFile() {            // TC-40
        let doc = app.newDocument()
        XCTAssertTrue(doc.playlist.tracks.isEmpty)
        XCTAssertNil(doc.fileURL)
        XCTAssertEqual(doc.windowControllers.count, 1)
        XCTAssertTrue(doc.displayName.hasPrefix("Untitled"))
        XCTAssertFalse(app.window(of: doc).emptyHint.isHidden, "an invitation to add files")
    }

    func testFirstSavePanelStartsInDocuments() {                              // TC-41
        let doc = app.newDocument()
        let panel = NSSavePanel()
        XCTAssertTrue(doc.prepareSavePanel(panel))
        XCTAssertEqual(panel.directoryURL, FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
    }

    func testFirstSaveWritesAtChosenPlaceAndTitleBecomesFileName() {          // TC-42
        let doc = app.newDocument()
        doc.addFiles(files(["track1.mp3", "tone.wav"]))
        let url = dir.path("Dinner.lplaylist")
        app.save(doc, to: url)
        XCTAssertEqual(doc.fileURL, url)
        XCTAssertEqual(doc.displayName, "Dinner")
        XCTAssertEqual(PlaylistStore().load(from: url), .loaded(doc.playlist))
    }

    func testEditingAnUntitledPlaylistWritesNoFileUntilFirstSave() {          // TC-52
        let doc = app.newDocument()
        doc.addFiles(files(["track1.mp3"]))
        spin(timeout: 0.3) { false }
        XCTAssertNil(doc.fileURL)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.url.path).isEmpty)
    }

    func testFirstSaveFailureShowsNoticeAndStaysUntitled() {                  // TC-44
        final class FailingStore: PlaylistStoring {
            func save(_ p: Playlist, to url: URL) -> SaveResult { .writeFailed("The disk is full.") }
            func load(from url: URL) -> LoadResult { .notFound }
        }
        app = TestApp(store: FailingStore())
        let doc = app.newDocument()
        var finished = false
        doc.save(to: dir.path("X.lplaylist"), ofType: playlistTypeIdentifier, for: .saveOperation) { _ in finished = true }
        spin { finished }
        XCTAssertEqual(app.notices.shown, [.saveFailed("The disk is full.")])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path("X.lplaylist").path))
    }

    func testOpenSavedPlaylistShowsFilesInSavedOrder() {                       // TC-45
        let fixture = PlaylistFixture(trackNames: ["track3.mp3", "track1.mp3", "track2.mp3"])
        let doc = app.openSaved(fixture.playlist, at: dir.path("Order.lplaylist"))
        XCTAssertEqual(doc.playlist.tracks.map(\.reference.fileName), ["track3.mp3", "track1.mp3", "track2.mp3"])
        XCTAssertEqual(doc.windowControllers.count, 1)
        XCTAssertEqual(app.window(of: doc).tableView.numberOfRows, 3)
    }

    func testOpeningTheSameFileTwiceGivesOneDocumentAndOneWindow() {           // TC-46 / TC-97
        let url = dir.path("Once.lplaylist")
        let first = app.openSaved(PlaylistFixture(trackNames: ["track1.mp3"]).playlist, at: url)
        var second: NSDocument?
        var done = false
        app.controller.openDocument(withContentsOf: url, display: true) { document, _, _ in second = document; done = true }
        spin { done }
        XCTAssertTrue(second === first)
        XCTAssertEqual(app.controller.playlistDocuments.filter { $0.fileURL == url }.count, 1)
        XCTAssertEqual(first.windowControllers.count, 1)
    }

    func testTwoDifferentPlaylistsGetTwoWindows() {                            // TC-47 / TC-34 of story 3
        let a = app.openSaved(PlaylistFixture(trackNames: ["track1.mp3"]).playlist, at: dir.path("A.lplaylist"))
        let b = app.openSaved(PlaylistFixture(trackNames: ["track2.mp3"]).playlist, at: dir.path("B.lplaylist"))
        XCTAssertFalse(a === b)
        XCTAssertNotNil(a.windowControllers.first?.window)
        XCTAssertNotNil(b.windowControllers.first?.window)
    }

    func testUnreadableFilesCreateNoDocumentAndChangeNothing() {               // TC-48
        let cases: [(String, Data)] = [("random.lplaylist", Data((0..<200).map { _ in UInt8.random(in: 0...255) })),
                                       ("newer.lplaylist", Data("{\"version\": 9, \"tracks\": []}".utf8)),
                                       ("empty.lplaylist", Data())]
        for (name, data) in cases {
            let url = dir.path(name)
            try! data.write(to: url)
            let before = try! Data(contentsOf: url)
            var error: Error?, document: NSDocument?, done = false
            let before2 = app.controller.documents.count
            app.controller.openDocument(withContentsOf: url, display: true) { doc, _, err in document = doc; error = err; done = true }
            spin { done }
            XCTAssertNil(document, name)
            XCTAssertNotNil(error, name)
            XCTAssertEqual(app.controller.documents.count, before2, "no window kept: \(name)")
            XCTAssertEqual(try! Data(contentsOf: url), before)
        }
        var error: Error?, done = false
        app.controller.openDocument(withContentsOf: dir.path("nope.lplaylist"), display: true) { _, _, err in error = err; done = true }
        spin { done }
        XCTAssertNotNil(error)
    }

    func testEditAutosavesWithoutAnyExplicitSave() {                           // TC-51
        let url = dir.path("Auto.lplaylist")
        let doc = app.openSaved(Playlist(), at: url)
        doc.addFiles(files(["track1.mp3", "tone.wav"]))
        waitForAutosave(doc)
        guard case .loaded(let onDisk) = PlaylistStore().load(from: url) else { return XCTFail() }
        XCTAssertEqual(onDisk, doc.playlist)
        XCTAssertEqual(onDisk.tracks.count, 2)
    }

    func testRenameChangesFileNameKeepsContentAndStaysOpen() {                  // TC-49 / TC-93
        let url = dir.path("Dinner.lplaylist")
        let fixture = PlaylistFixture(trackNames: ["track1.mp3", "track2.mp3"])
        let doc = app.openSaved(fixture.playlist, at: url)
        var result: Result<Void, PlaylistDocument.RenameError>?
        doc.renameFile(to: "Supper") { result = $0 }
        spin { result != nil }
        XCTAssertNoThrow(try result?.get())
        XCTAssertEqual(doc.fileURL?.lastPathComponent, "Supper.lplaylist")
        XCTAssertEqual(doc.displayName, "Supper")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(PlaylistStore().load(from: dir.path("Supper.lplaylist")), .loaded(fixture.playlist))
        XCTAssertEqual(app.controller.documents.count, 1)
    }

    func testRenameFailuresKeepOldNameAndFile() {                               // TC-50
        let url = dir.path("Dinner.lplaylist")
        let doc = app.openSaved(Playlist(), at: url)
        try! Data().write(to: dir.path("Taken.lplaylist"))
        for bad in ["Taken", "", "a/b"] {
            var result: Result<Void, PlaylistDocument.RenameError>?
            doc.renameFile(to: bad) { result = $0 }
            spin { result != nil }
            XCTAssertThrowsError(try result?.get(), bad)
            XCTAssertEqual(doc.fileURL, url)
        }
        let untitled = app.newDocument()
        var result: Result<Void, PlaylistDocument.RenameError>?
        untitled.renameFile(to: "X") { result = $0 }
        XCTAssertThrowsError(try result?.get())
    }

    // MARK: self-update (TC-60..TC-63, TC-98)

    func testRefreshedReferenceChangesOnlyThatTrackAndIsAutosaved() {          // TC-60
        let url = dir.path("Refresh.lplaylist")
        let fixture = PlaylistFixture()
        let doc = app.openSaved(fixture.playlist, at: url)
        var newReference = fixture.tracks[2].reference
        newReference.lastKnownPath = "/changed/track3.mp3"
        doc.apply(newReference, toTrack: fixture.tracks[2].id)
        doc.apply(newReference, toTrack: UUID())            // an id no track has changes nothing
        waitForAutosave(doc)
        guard case .loaded(let onDisk) = PlaylistStore().load(from: url) else { return XCTFail() }
        XCTAssertEqual(onDisk.tracks[2].reference, newReference)
        XCTAssertEqual(onDisk.tracks.map(\.id), fixture.tracks.map(\.id))
        for index in [0, 1, 3, 4] { XCTAssertEqual(onDisk.tracks[index], fixture.tracks[index]) }
        XCTAssertEqual(doc.fileURL, url)
    }

    func testSeveralAppliesAreWrittenByOneAutosave() {
        final class CountingStore: PlaylistStoring {
            var saves = 0
            let real = PlaylistStore()
            func save(_ p: Playlist, to url: URL) -> SaveResult { saves += 1; return real.save(p, to: url) }
            func load(from url: URL) -> LoadResult { real.load(from: url) }
        }
        let counting = CountingStore()
        app = TestApp(store: counting)
        let fixture = PlaylistFixture()
        let doc = app.openSaved(fixture.playlist, at: dir.path("Batch.lplaylist"))
        let savesBefore = counting.saves
        for track in fixture.tracks {
            var reference = track.reference; reference.lastKnownPath += ".moved"
            doc.apply(reference, toTrack: track.id)
        }
        waitForAutosave(doc)
        XCTAssertEqual(counting.saves - savesBefore, 1)
    }

    func testOpeningAPlaylistWithUnmovedFilesDoesNotEditTheDocument() {         // TC-01 of story 5
        let fixture = PlaylistFixture()
        let doc = app.openSaved(fixture.playlist, at: dir.path("Calm.lplaylist"))
        var done = false
        doc.resolveStatuses { done = true }
        spin { done }
        XCTAssertFalse(doc.isDocumentEdited)
        for track in fixture.tracks { XCTAssertEqual(doc.statuses.status(of: track.id), .resolved(fixture.urls[fixture.tracks.firstIndex(of: track)!])) }
    }

    func testMovedFilesAreFollowedAndRefreshedReferencesSaved() {               // TC-03 / E2E-8
        let fixture = PlaylistFixture()
        let url = dir.path("Moved.lplaylist")
        let doc = app.openSaved(fixture.playlist, at: url)
        let elsewhere = audio.makeSubfolder("moved")
        for index in 0..<2 {
            try! FileManager.default.moveItem(at: fixture.urls[index], to: elsewhere.appendingPathComponent(fixture.urls[index].lastPathComponent))
        }
        var done = false
        doc.resolveStatuses { done = true }
        spin { done }
        waitForAutosave(doc)
        guard case .loaded(let onDisk) = PlaylistStore().load(from: url) else { return XCTFail() }
        XCTAssertEqual(onDisk.tracks[0].reference.lastKnownPath, elsewhere.appendingPathComponent("track1.mp3").canonicalPath)
        XCTAssertEqual(onDisk.tracks[2].reference, fixture.tracks[2].reference, "untouched tracks unchanged")
        XCTAssertEqual(doc.statuses.status(of: fixture.tracks[0].id), .resolved(elsewhere.appendingPathComponent("track1.mp3")))
    }

    func testMissingTracksAreGreyedAndNotEdited() {                              // TC-05/07/62
        let fixture = PlaylistFixture()
        let doc = app.openSaved(fixture.playlist, at: dir.path("Gone.lplaylist"))
        fixture.deleteFile(at: 1)
        var done = false
        doc.resolveStatuses { done = true }
        spin { done }
        XCTAssertEqual(doc.statuses.status(of: fixture.tracks[1].id), .missing)
        XCTAssertFalse(doc.isDocumentEdited)
        XCTAssertTrue(app.notices.shown.isEmpty, "no dialog on open")
        let window = app.window(of: doc)
        window.reload()
        let cell = window.tableView.view(atColumn: 0, row: 1, makeIfNecessary: true) as! TrackCellView
        XCTAssertTrue(cell.isGreyedOut)
        XCTAssertFalse(cell.showsHazard, "no hazard icon until a play is attempted")
        XCTAssertFalse((window.tableView.view(atColumn: 0, row: 0, makeIfNecessary: true) as! TrackCellView).isGreyedOut)
        XCTAssertEqual(doc.playlist.tracks.count, 5, "a missing track is never removed automatically")
    }

    // MARK: editor (TC-80..TC-85)

    func testDropAddsRowsInOrderAndAutosaves() {                                 // TC-81
        let url = dir.path("Drop.lplaylist")
        let doc = app.openSaved(Playlist(), at: url)
        let window = app.window(of: doc)
        doc.addFiles(files(["track1.mp3", "tone.wav", "tone.m4a"]))
        XCTAssertEqual(window.tableView.numberOfRows, 3)
        XCTAssertTrue(window.emptyHint.isHidden)
        waitForAutosave(doc)
        guard case .loaded(let onDisk) = PlaylistStore().load(from: url) else { return XCTFail() }
        XCTAssertEqual(onDisk.tracks.map(\.reference.fileName), ["track1.mp3", "tone.wav", "tone.m4a"])
    }

    func testReorderByDragMovesTheRow() {                                         // TC-82
        let doc = app.openSaved(PlaylistFixture(trackNames: ["track1.mp3", "track2.mp3", "track3.mp3"]).playlist, at: dir.path("R.lplaylist"))
        let window = app.window(of: doc)
        XCTAssertTrue(window.reorder(rows: [2], toBefore: 0))
        XCTAssertEqual(doc.playlist.tracks.map(\.reference.fileName), ["track3.mp3", "track1.mp3", "track2.mp3"])
        XCTAssertTrue(window.reorder(rows: [0, 1], toBefore: 3))
        XCTAssertEqual(doc.playlist.tracks.map(\.reference.fileName), ["track2.mp3", "track3.mp3", "track1.mp3"])
        XCTAssertFalse(window.reorder(rows: [9], toBefore: 0))
    }

    func testUnsupportedDropShowsNoticeAndLeavesRowsAndFileAlone() {              // TC-83 / TC-91
        let url = dir.path("U.lplaylist")
        let doc = app.openSaved(PlaylistFixture(trackNames: ["track1.mp3"]).playlist, at: url)
        let before = try! Data(contentsOf: url)
        let result = doc.addFiles([Fixtures.url("tone.flac")])
        XCTAssertEqual(result.rejected.count, 1)
        XCTAssertEqual(doc.playlist.tracks.count, 1)
        XCTAssertEqual(app.notices.shown.count, 1)
        guard case .unsupported = app.notices.shown[0] else { return XCTFail() }
        spin(timeout: 0.3) { false }
        XCTAssertEqual(try! Data(contentsOf: url), before, "playlist file not rewritten")
    }

    func testRemoveSelectedRowKeepsAudioFile() {                                   // TC-85 / TC-90
        let fixture = PlaylistFixture()
        let doc = app.openSaved(fixture.playlist, at: dir.path("Rm.lplaylist"))
        let window = app.window(of: doc)
        let snapshot = FileSnapshot(fixture.urls[2])
        window.tableView.selectRowIndexes([2], byExtendingSelection: false)
        window.removeSelectedTracks(nil)
        XCTAssertEqual(doc.playlist.tracks.count, 4)
        XCTAssertFalse(doc.playlist.tracks.contains { $0.id == fixture.tracks[2].id })
        XCTAssertEqual(FileSnapshot(fixture.urls[2]), snapshot)
        XCTAssertEqual(window.tableView.numberOfRows, 4)
    }

    func testRemovingTheLastFileLeavesAnEmptyPlaylist() {
        let doc = app.openSaved(PlaylistFixture(trackNames: ["track1.mp3"]).playlist, at: dir.path("L.lplaylist"))
        let window = app.window(of: doc)
        window.tableView.selectRowIndexes([0], byExtendingSelection: false)
        window.removeSelectedTracks(nil)
        XCTAssertTrue(doc.playlist.tracks.isEmpty)
        XCTAssertFalse(window.emptyHint.isHidden)
        XCTAssertFalse(window.removeButton.isEnabled)
    }

    func testSaveFailureAfterEditKeepsRowsAndShowsNotice() {                        // TC-84
        final class FlakyStore: PlaylistStoring {
            var failing = false
            let real = PlaylistStore()
            func save(_ p: Playlist, to url: URL) -> SaveResult { failing ? .writeFailed("The folder is read-only.") : real.save(p, to: url) }
            func load(from url: URL) -> LoadResult { real.load(from: url) }
        }
        let flaky = FlakyStore()
        app = TestApp(store: flaky)
        let url = dir.path("F.lplaylist")
        let doc = app.openSaved(PlaylistFixture(trackNames: ["track1.mp3"]).playlist, at: url)
        let onDiskBefore = try! Data(contentsOf: url)
        flaky.failing = true
        doc.addFiles(files(["tone.wav"]))
        spin { !self.app.notices.shown.isEmpty }
        XCTAssertEqual(app.notices.shown.first, .saveFailed("The folder is read-only."))
        XCTAssertEqual(doc.playlist.tracks.count, 2, "rows show the edit")
        XCTAssertEqual(try! Data(contentsOf: url), onDiskBefore, "disk keeps its previous version")
    }

    // MARK: Locate through the window (story 5)

    func testLocateMenuIsOfferedOnlyOnMissingRows() {                               // TC-63
        let fixture = PlaylistFixture()
        let doc = app.openSaved(fixture.playlist, at: dir.path("Loc.lplaylist"))
        fixture.deleteFile(at: 3)
        var done = false
        doc.resolveStatuses { done = true }
        spin { done }
        let window = app.window(of: doc)
        XCTAssertEqual(window.locateMenuItems(forRow: 3).map(\.title), ["Locate…"])
        for present in [0, 1, 2, 4, -1, 99] { XCTAssertTrue(window.locateMenuItems(forRow: present).isEmpty, "row \(present)") }
    }

    func testLocateRepairsMissingTracksAndSurvivesReopen() {                         // TC-17 / TC-45 / E2E-3
        let fixture = PlaylistFixture()
        let url = dir.path("Fix.lplaylist")
        let doc = app.openSaved(fixture.playlist, at: url)
        let copy = TempDir("newhome")
        for index in [1, 3] { fixture.deleteFile(at: index) }
        try! FileManager.default.copyItem(at: Fixtures.url("track2.mp3"), to: copy.path("track2.mp3"))
        try! FileManager.default.copyItem(at: Fixtures.url("track4.mp3"), to: copy.path("track4.mp3"))
        var done = false
        doc.resolveStatuses { done = true }
        spin { done }
        let window = app.window(of: doc)
        window.chooseFileToLocate = { copy.path("track2.mp3") }
        let item = NSMenuItem(); item.representedObject = fixture.tracks[1].id
        window.locateTrack(item)
        XCTAssertEqual(doc.statuses.status(of: fixture.tracks[1].id), .resolved(copy.path("track2.mp3")))
        XCTAssertEqual(doc.statuses.status(of: fixture.tracks[3].id), .resolved(copy.path("track4.mp3")), "same-folder match")
        waitForAutosave(doc)
        doc.close()
        let reopened = app.openSaved(PlaylistStore().load(from: url).playlistValue!, at: url)
        var again = false
        reopened.resolveStatuses { again = true }
        spin { again }
        XCTAssertEqual(reopened.statuses.status(of: fixture.tracks[1].id), .resolved(copy.path("track2.mp3")),
                       "repaired tracks are still normal after reopening, with no Locate")
    }

    func testCancelledLocateChangesNothing() {                                        // TC-64
        let fixture = PlaylistFixture()
        let doc = app.openSaved(fixture.playlist, at: dir.path("C.lplaylist"))
        fixture.deleteFile(at: 1)
        var done = false
        doc.resolveStatuses { done = true }
        spin { done }
        let window = app.window(of: doc)
        window.chooseFileToLocate = { nil }
        let item = NSMenuItem(); item.representedObject = fixture.tracks[1].id
        window.locateTrack(item)
        XCTAssertEqual(doc.statuses.status(of: fixture.tracks[1].id), .missing)
        XCTAssertFalse(doc.isDocumentEdited)
    }

    func testDoubleClickingAMissingRowMarksItWithoutADialog() {                        // TC-08 / TC-70 / TC-73
        let fixture = PlaylistFixture()
        let doc = app.openSaved(fixture.playlist, at: dir.path("D.lplaylist"))
        fixture.deleteFile(at: 2)
        doc.player.play(track: fixture.tracks[2])
        doc.player.play(track: fixture.tracks[2])
        XCTAssertEqual(app.services.marks.mark(of: fixture.tracks[2]), .unreadable)
        XCTAssertTrue(app.backend.log.isEmpty)
        XCTAssertTrue(app.notices.shown.isEmpty)
        let window = app.window(of: doc)
        window.reload()
        XCTAssertTrue((window.tableView.view(atColumn: 0, row: 2, makeIfNecessary: true) as! TrackCellView).showsHazard)
        XCTAssertFalse((window.tableView.view(atColumn: 0, row: 1, makeIfNecessary: true) as! TrackCellView).showsHazard)
        XCTAssertFalse(doc.isDocumentEdited, "the mark is session-only and never written (TC-74)")
    }
}

extension LoadResult {
    var playlistValue: Playlist? { if case .loaded(let p) = self { return p } else { return nil } }
}
