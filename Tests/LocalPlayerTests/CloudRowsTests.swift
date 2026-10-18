import XCTest
import AppKit
@testable import LocalPlayer
@testable import PlayawayCore

/// Story 20 on the Mac: each row of a synced playlist carries a cloud icon at its right-hand end (outline, crossed-out,
/// pie, exclamation mark), the row is dimmed only when its file is not on this Mac, playing a song that is not here
/// downloads it first and plays it when it arrives, and the icon is a control with story 31's rules. A temp folder
/// stands in for the Playaway folder and a scripted provider for iCloud; real iCloud is not exercised.
@MainActor
final class CloudRowsTests: XCTestCase {
    var app: TestApp!
    let cloud = TempDir("rowscloud")
    let docs = TempDir("rowsdocs")
    var songs: ScriptedCloudSongs!
    private var fixtures: [PlaylistFixture] = []

    override func setUp() async throws {
        let root = cloud.url
        songs = ScriptedCloudSongs(root: { root })
        app = TestApp(cloudRoot: { root }, cloudSongs: songs)
    }
    override func tearDown() async throws { app.tearDown() }

    /// A synced playlist (its file inside the stand-in folder) with three songs: one in iCloud and here, one outside
    /// iCloud, one in iCloud but not on this Mac.
    private func openSynced(order: [String] = ["inside", "outside", "absent"]) throws -> (doc: PlaylistDocument, inside: URL, outside: URL, absent: URL) {
        let folder = cloud.url.appendingPathComponent("Dinner")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let inside = folder.appendingPathComponent("track1.mp3"), absent = folder.appendingPathComponent("track3.mp3")
        try FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: inside)
        try FileManager.default.copyItem(at: Fixtures.url("track3.mp3"), to: absent)
        let outsideFixture = PlaylistFixture(trackNames: ["track2.mp3"])
        fixtures.append(outsideFixture)
        let outside = outsideFixture.urls[0]
        songs.notOnDevice.insert(absent.canonicalPath)
        let byName = ["inside": inside, "outside": outside, "absent": absent]
        let tracks = order.map { Track(id: UUID(), reference: TrackReference.make(for: byName[$0]!)!) }
        let doc = app.openSaved(Playlist(tracks: tracks), at: folder.appendingPathComponent("Dinner.\(playlistFileExtension)"))
        var done = false; doc.resolveStatuses { done = true }; spin { done }
        app.window(of: doc).reload()
        return (doc, inside, outside, absent)
    }

    private func cell(_ doc: PlaylistDocument, _ row: Int) -> TrackCellView {
        app.window(of: doc).tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as! TrackCellView
    }

    func testEachRowShowsWhereItsSongIsAndIsDimmedOnlyWhenTheFileIsNotHere() throws {                 // TC-01, TC-02, TC-70, TC-16
        let (doc, _, _, _) = try openSynced()
        XCTAssertEqual(cell(doc, 0).cloudKind, .outline); XCTAssertFalse(cell(doc, 0).isGreyedOut)
        XCTAssertTrue(cell(doc, 0).accessibilityLabel()?.hasSuffix(", in iCloud") == true, cell(doc, 0).accessibilityLabel() ?? "")
        XCTAssertEqual(cell(doc, 1).cloudKind, .crossedOut); XCTAssertFalse(cell(doc, 1).isGreyedOut, "local, plays, not dimmed")
        XCTAssertTrue(cell(doc, 1).accessibilityLabel()?.hasSuffix(", not in iCloud") == true)
        XCTAssertEqual(cell(doc, 2).cloudKind, .outline); XCTAssertTrue(cell(doc, 2).isGreyedOut, "in iCloud, not here: dimmed")
        XCTAssertTrue(cell(doc, 2).accessibilityLabel()?.hasSuffix(", not on this Mac") == true, cell(doc, 2).accessibilityLabel() ?? "")
        XCTAssertEqual(cell(doc, 0).cloudOpacity, 0.5, "quiet icons")
    }

    func testAPlaylistThatIsNotSyncedShowsNoCloudState() {                                      // TC-09, TC-69
        let fixture = PlaylistFixture(trackNames: ["track1.mp3", "track2.mp3"])
        fixtures.append(fixture)
        let doc = app.openSaved(fixture.playlist, at: docs.path("Local.\(playlistFileExtension)"))
        var done = false; doc.resolveStatuses { done = true }; spin { done }
        app.window(of: doc).reload()
        XCTAssertNil(cell(doc, 0).cloudKind)
        XCTAssertNil(cell(doc, 1).cloudKind)
        XCTAssertFalse(cell(doc, 0).accessibilityLabel()?.contains("iCloud") == true)
    }

    func testPlayingASongNotOnThisMacDownloadsItShowsThePieAndPlaysItWhenItArrives() throws {          // TC-71, TC-73, TC-78, TC-83
        let (doc, _, _, absent) = try openSynced()
        let window = app.window(of: doc)
        window.playRow(2)
        XCTAssertNil(app.services.engine.currentURL, "nothing plays yet")
        XCTAssertEqual(songs.started, [MacSongs.id(for: absent)])
        XCTAssertEqual(cell(doc, 2).cloudKind, .pieDownload); XCTAssertTrue(cell(doc, 2).isGreyedOut)
        XCTAssertTrue(cell(doc, 2).accessibilityLabel()?.hasSuffix(", downloading from iCloud") == true)
        songs.progress(absent, percent: 50)
        XCTAssertEqual(cell(doc, 2).pieFraction, 0.5)
        songs.finish(absent)
        XCTAssertEqual(app.services.engine.currentURL, absent, "it plays when it arrives")
        XCTAssertEqual(cell(doc, 2).cloudKind, .outline); XCTAssertFalse(cell(doc, 2).isGreyedOut)
    }

    func testChoosingAnotherSongWhileItDownloadsKeepsTheFileWithoutInterrupting() throws {              // TC-74
        let (doc, inside, _, absent) = try openSynced()
        let window = app.window(of: doc)
        window.playRow(2)
        window.playRow(0)
        XCTAssertEqual(app.services.engine.currentURL, inside)
        songs.finish(absent)
        XCTAssertEqual(app.services.engine.currentURL, inside, "not interrupted")
        XCTAssertEqual(cell(doc, 2).cloudKind, .outline); XCTAssertFalse(cell(doc, 2).isGreyedOut, "the file is here now")
    }

    func testTransportPlayDoesNothingWhileTheCurrentSongDownloads() throws {                           // TC-80
        let (doc, _, _, _) = try openSynced()
        app.window(of: doc).playRow(2)
        app.services.transport.playPause()
        XCTAssertNil(app.services.engine.currentURL)
        XCTAssertEqual(app.services.engine.state, .idle)
    }

    func testAFailedDownloadShowsTheExclamationMarkAndAClickOnItRetries() throws {                     // TC-86, TC-87, TC-92, TC-95
        let (doc, _, _, absent) = try openSynced()
        let window = app.window(of: doc)
        window.playRow(2)
        songs.fail(absent)
        XCTAssertEqual(cell(doc, 2).cloudKind, .exclamation); XCTAssertTrue(cell(doc, 2).isGreyedOut)
        XCTAssertTrue(cell(doc, 2).accessibilityLabel()?.hasSuffix(", Download failed, tap to retry") == true)
        XCTAssertNil(app.services.engine.currentURL)
        XCTAssertEqual(songs.started.count, 1, "no retry without a click")
        cell(doc, 2).cloudButton.performClick(nil)
        XCTAssertEqual(songs.started.count, 2, "one retry")
        XCTAssertEqual(cell(doc, 2).cloudKind, .pieDownload)
        songs.finish(absent)
        XCTAssertEqual(app.services.engine.currentURL, absent, "plays at the end, still current")
    }

    func testAClickOnThePieCancelsTheDownloadAndTheRowReturnsToTheOutlineCloudDimmed() throws {        // TC-91
        let (doc, _, _, absent) = try openSynced()
        app.window(of: doc).playRow(2)
        cell(doc, 2).cloudButton.performClick(nil)
        XCTAssertEqual(songs.cancelled, [MacSongs.id(for: absent)])
        XCTAssertEqual(cell(doc, 2).cloudKind, .outline); XCTAssertTrue(cell(doc, 2).isGreyedOut)
        XCTAssertNil(app.services.engine.currentURL)
        songs.finish(absent)                                                 // a late finish after the cancel
        XCTAssertNil(app.services.engine.currentURL, "nothing plays")
    }

    func testAClickOnTheCrossedOutCloudAsksTheFilesQuestionForThatSongOnly() throws {           // TC-89, TC-94
        let (doc, _, outside, _) = try openSynced()
        let window = app.window(of: doc)
        var asked = 0
        window.askFilesChoice = { asked += 1; return .doNothing }
        cell(doc, 1).cloudButton.performClick(nil)
        spin { asked == 1 }
        XCTAssertEqual(asked, 1)
        XCTAssertNil(app.services.engine.currentURL, "the click never plays the row")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path), "Add Without Syncing: nothing moved")
        XCTAssertEqual(cell(doc, 1).cloudKind, .crossedOut)
        // And with Copy to iCloud the song lands beside the playlist and the row becomes the outline cloud.
        window.askFilesChoice = { .copyToICloud }
        cell(doc, 1).cloudButton.performClick(nil)
        spin { self.cell(doc, 1).cloudKind == .outline }
        XCTAssertEqual(cell(doc, 1).cloudKind, .outline)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cloud.url.appendingPathComponent("Dinner/track2.mp3").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path), "the original stays")
        XCTAssertEqual(doc.playlist.tracks.count, 3, "same rows")
    }

    func testAClickOnTheOutlineCloudDoesNothing() throws {                                              // TC-90, TC-94
        let (doc, _, _, _) = try openSynced()
        let window = app.window(of: doc)
        var asked = 0
        window.askFilesChoice = { asked += 1; return .doNothing }
        cell(doc, 0).cloudButton.performClick(nil)
        spin(timeout: 0.3) { false }
        XCTAssertEqual(asked, 0)
        XCTAssertEqual(songs.started, [])
        XCTAssertNil(app.services.engine.currentURL)
        XCTAssertEqual(cell(doc, 0).cloudKind, .outline)
    }

    /// Task 20.23: the song the person asked for plays when it arrives even though the song that was playing has
    /// ended and the playlist ran out meanwhile; running out is not the person moving on.
    func testTheAskedForSongStillPlaysWhenTheSongBeforeItEndedAndThePlaylistRanOut() throws {          // 20.23 (1)
        let (doc, inside, _, absent) = try openSynced(order: ["inside", "absent"])
        let window = app.window(of: doc)
        window.playRow(0)
        XCTAssertEqual(app.services.engine.currentURL, inside)
        window.playRow(1)                                                    // asked for while the first one plays
        XCTAssertEqual(songs.started, [MacSongs.id(for: absent)])
        app.backend.playing?.finish()                                        // the first song ends; the absent one is skipped; the playlist runs out
        spin { !doc.player.isSessionActive }
        XCTAssertFalse(doc.player.isSessionActive)
        XCTAssertNil(doc.player.current)
        songs.finish(absent)
        XCTAssertEqual(app.services.engine.currentURL, absent, "it plays when it arrives: nothing else was asked for")
        XCTAssertEqual(cell(doc, 1).cloudKind, .outline); XCTAssertFalse(cell(doc, 1).isGreyedOut)
    }

    /// Task 20.23: a playlist started on its first song, which is not on this Mac: the play-through asks for it, runs
    /// out, and the song plays when it arrives.
    func testAPlaylistStartedOnASongNotOnThisMacPlaysItWhenItArrives() throws {                       // 20.23 (2)
        let (doc, _, _, absent) = try openSynced(order: ["absent"])
        doc.player.start()
        XCTAssertEqual(songs.started, [MacSongs.id(for: absent)], "asked for by the play-through")
        XCTAssertNil(app.services.engine.currentURL)
        XCTAssertFalse(doc.player.isSessionActive, "nothing playable yet: the session ended")
        songs.finish(absent)
        XCTAssertEqual(app.services.engine.currentURL, absent, "it plays when it arrives")
    }

    func testPlayingThroughSkipsASongNotOnThisMacAndAsksForItWithoutPlayingItLater() throws {          // TC-79 (start, next, auto-advance)
        let (doc, inside, outside, absent) = try openSynced(order: ["inside", "absent", "outside"])
        doc.player.start()
        XCTAssertEqual(app.services.engine.currentURL, inside)
        doc.player.next()
        XCTAssertEqual(app.services.engine.currentURL, outside, "the absent song is skipped")
        XCTAssertEqual(songs.started, [MacSongs.id(for: absent)], "and asked for")
        songs.finish(absent)
        XCTAssertEqual(app.services.engine.currentURL, outside, "the person moved on: the file is kept, nothing is interrupted")
        XCTAssertEqual(cell(doc, 1).cloudKind, .outline); XCTAssertFalse(cell(doc, 1).isGreyedOut)
    }
}
