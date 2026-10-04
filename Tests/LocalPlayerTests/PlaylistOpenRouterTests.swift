import XCTest
import AppKit
@testable import LocalPlayer

@MainActor
final class PlaylistOpenRouterTests: XCTestCase {
    var app: TestApp!
    let dir = TempDir("router")
    var actions: [OpenAction] = []
    var keepAlive: [PlaylistFixture] = []   // a fixture deletes its audio files when released

    override func setUp() async throws {
        app = TestApp()
        app.services.playlistRouter.didOpen = { [unowned self] _, action in self.actions.append(action) }
    }
    override func tearDown() async throws { app.tearDown() }

    /// Delivers a playlist URL the way the open-files event does, and waits for the router to finish.
    func finderOpen(_ url: URL) {
        let before = actions.count
        app.services.openCoordinator.open([url])
        spin { self.actions.count > before }
    }

    func save(_ fixture: PlaylistFixture, as name: String) -> URL {
        keepAlive.append(fixture)
        let url = dir.path(name)
        XCTAssertEqual(PlaylistStore().save(fixture.playlist, to: url), .saved)
        return url
    }

    func started() -> [String] { app.backend.startedNames }
    func closeWindow(for url: URL) { (app.controller.document(for: url))?.close() }

    // MARK: start position by shuffle (TC-01..TC-08)

    func testNotOpenStartsFirstTrackWithShuffleOff() {                                 // TC-01
        let url = save(PlaylistFixture(), as: "A.lplaylist")
        finderOpen(url)
        XCTAssertEqual(actions, [.showAndStart])
        XCTAssertEqual(app.controller.playlistDocuments.count, 1)
        XCTAssertEqual(started(), ["track1.mp3"])
    }

    func testNotOpenStartsAtSeededRandomTrackWithShuffleOn() {                          // TC-02 / prd.plopen.random
        app.services.settings.setShuffle(true)
        let fixture = PlaylistFixture()
        let url = save(fixture, as: "A.lplaylist")
        finderOpen(url)
        let doc = app.controller.document(for: url) as! PlaylistDocument
        let expected = seededShuffler().pass(for: doc.playlist, startingWith: nil)[0]
        XCTAssertEqual(started(), [expected.reference.fileName])
    }

    func testOpenButIdleBringsWindowFrontAndStartsWithoutSecondWindow() {                // TC-03/04/32
        for shuffle in [false, true] {
            app.services.settings.setShuffle(shuffle)
            let url = save(PlaylistFixture(), as: "Idle\(shuffle).lplaylist")
            var opened: NSDocument?, done = false
            app.controller.openDocument(withContentsOf: url, display: true) { d, _, _ in opened = d; done = true }
            spin { done }
            XCTAssertFalse((opened as! PlaylistDocument).player.isPlaying)
            let before = started().count
            finderOpen(url)
            XCTAssertEqual(actions.last, .showAndStart)
            XCTAssertEqual(started().count, before + 1)
            XCTAssertEqual(app.controller.playlistDocuments.filter { $0.fileURL == url }.count, 1, "one window")
            finderOpen(url)                                                               // TC-32: twice in a row
            XCTAssertEqual(app.controller.playlistDocuments.filter { $0.fileURL == url }.count, 1)
            app.services.engine.stop()
        }
    }

    func testAlreadyPlayingIsLeftAlone() {                                                // TC-05/06/40
        for shuffle in [false, true] {
            app.services.settings.setShuffle(shuffle)
            let url = save(PlaylistFixture(), as: "Playing\(shuffle).lplaylist")
            finderOpen(url)
            app.backend.latest!.currentTime = 2.5
            let logBefore = app.backend.log
            let modes = (app.services.settings.shuffleOn, app.services.settings.repeatMode)
            finderOpen(url)
            XCTAssertEqual(actions.last, .focusOnly)
            XCTAssertEqual(app.backend.log, logBefore, "no restart, no start call")
            XCTAssertEqual(app.services.engine.position, 2.5)
            XCTAssertEqual(app.services.settings.shuffleOn, modes.0)
            XCTAssertEqual(app.services.settings.repeatMode, modes.1)
            XCTAssertEqual(app.controller.playlistDocuments.filter { $0.fileURL == url }.count, 1)
            app.services.engine.stop()
        }
    }

    func testDifferentPlaylistPlayingIsStopped() {                                        // TC-07/08
        let first = save(PlaylistFixture(), as: "First.lplaylist")
        let second = save(PlaylistFixture(trackNames: ["track4.mp3", "track5.mp3"]), as: "Second.lplaylist")
        finderOpen(first)
        let firstDoc = app.controller.document(for: first) as! PlaylistDocument
        finderOpen(second)
        XCTAssertFalse(firstDoc.player.isPlaying)
        XCTAssertEqual(app.services.engine.currentURL?.lastPathComponent, "track4.mp3")
        app.backend.playing?.finish()
        XCTAssertEqual(started().suffix(2), ["track4.mp3", "track5.mp3"], "only the second plays on")
        XCTAssertEqual(app.controller.playlistDocuments.count, 2, "other windows are never closed")
    }

    func testOnePlaylistWithOneTrackAndShuffle() {                                        // TC-27
        app.services.settings.setShuffle(true)
        finderOpen(save(PlaylistFixture(trackNames: ["track2.mp3"]), as: "One.lplaylist"))
        XCTAssertEqual(started(), ["track2.mp3"])
    }

    // MARK: empty and unreadable (TC-28..31, TC-43)

    func testEmptyPlaylistShowsWindowStartsNothingAndStopsNothing() {                     // TC-28 / TC-22 / TC-43
        let busy = save(PlaylistFixture(), as: "Busy.lplaylist")
        finderOpen(busy)
        let empty = save(PlaylistFixture(trackNames: []), as: "Empty.lplaylist")
        finderOpen(empty)
        XCTAssertEqual(actions.last, .showOnly)
        XCTAssertNotNil(app.controller.document(for: empty))
        XCTAssertTrue(app.services.engine.isPlaying, "current playback untouched")
        XCTAssertEqual(started(), ["track1.mp3"])
    }

    func testUnreadablePlaylistsKeepNoWindowAndStopNothing() {                            // TC-29/30/31
        finderOpen(save(PlaylistFixture(), as: "Busy.lplaylist"))
        let documentsBefore = app.controller.documents.count
        let random = dir.path("random.lplaylist"); try! Data((0..<100).map { _ in UInt8.random(in: 0...255) }).write(to: random)
        let newer = dir.path("newer.lplaylist"); try! Data("{\"version\": 50, \"tracks\": []}".utf8).write(to: newer)
        for url in [random, newer, dir.path("missing.lplaylist")] {
            finderOpen(url)
            XCTAssertEqual(actions.last, .doNothing, url.lastPathComponent)
        }
        XCTAssertEqual(app.controller.documents.count, documentsBefore)
        XCTAssertTrue(app.services.engine.isPlaying)
        XCTAssertEqual(started(), ["track1.mp3"])
    }

    func testClosedWindowIsReopenedAndStartsAgain() {                                      // TC-33
        let url = save(PlaylistFixture(), as: "Again.lplaylist")
        finderOpen(url)
        closeWindow(for: url)
        app.services.engine.stop()
        finderOpen(url)
        XCTAssertEqual(actions.suffix(2), [.showAndStart, .showAndStart])
        XCTAssertEqual(app.controller.playlistDocuments.filter { $0.fileURL == url }.count, 1)
    }

    // MARK: content and settings untouched (TC-41, TC-42)

    func testOpeningNeverChangesSettingsOrPlaylistContent() {
        let fixture = PlaylistFixture()
        let url = save(fixture, as: "Same.lplaylist")
        let defaultsBefore = app.services.defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("shuffle") || $0.key.hasPrefix("repeat") }
        let bytes = try! Data(contentsOf: url)
        finderOpen(url)
        let doc = app.controller.document(for: url) as! PlaylistDocument
        XCTAssertEqual(doc.playlist, fixture.playlist)
        spin(timeout: 0.3) { false }
        XCTAssertEqual(try! Data(contentsOf: url), bytes, "unchanged files are not rewritten")
        let defaultsAfter = app.services.defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("shuffle") || $0.key.hasPrefix("repeat") }
        XCTAssertEqual(NSDictionary(dictionary: defaultsBefore), NSDictionary(dictionary: defaultsAfter))
    }

    // MARK: audio file replaces playlist playback (TC-35..38)

    func testOpeningAnAudioFileEndsThePlaylistAndPlaysTheFile() {
        let url = save(PlaylistFixture(), as: "P.lplaylist")
        finderOpen(url)
        let doc = app.controller.document(for: url) as! PlaylistDocument
        app.services.openCoordinator.open([Fixtures.url("tone.wav")])
        XCTAssertFalse(doc.player.isSessionActive)
        XCTAssertEqual(app.services.engine.currentURL, Fixtures.url("tone.wav"))
        app.backend.playing?.finish()
        XCTAssertEqual(started(), ["track1.mp3", "tone.wav"], "the playlist does not advance under the new file")
    }

    func testUnsupportedFileLeavesThePlaylistPlaying() {                                   // TC-36
        finderOpen(save(PlaylistFixture(), as: "P.lplaylist"))
        app.services.openCoordinator.open([Fixtures.url("tone.flac")])
        XCTAssertEqual(app.notices.shown.count, 1)
        XCTAssertTrue(app.services.engine.isPlaying)
        app.backend.playing?.finish()
        XCTAssertEqual(started(), ["track1.mp3", "track2.mp3"])
    }

    func testDecisionTableAndLoadMapping() {                                                // TC-20..TC-26
        XCTAssertEqual(PlaylistOpenDecision.decide(.withTracks, isPlaying: false), .showAndStart)
        XCTAssertEqual(PlaylistOpenDecision.decide(.empty, isPlaying: false), .showOnly)
        XCTAssertEqual(PlaylistOpenDecision.decide(.empty, isPlaying: true), .showOnly)
        XCTAssertEqual(PlaylistOpenDecision.decide(.withTracks, isPlaying: true), .focusOnly)
        XCTAssertEqual(PlaylistOpenDecision.decide(.unreadable, isPlaying: false), .doNothing)
        XCTAssertEqual(PlaylistOpenDecision.decide(.unreadable, isPlaying: true), .doNothing)
        XCTAssertEqual(OpenOutcome(.loaded(Playlist(tracks: bareTracks(5)))), .withTracks)
        XCTAssertEqual(OpenOutcome(.loaded(Playlist(tracks: bareTracks(1)))), .withTracks)
        XCTAssertEqual(OpenOutcome(.loaded(Playlist())), .empty)
        for load in [LoadResult.notFound, .corrupt, .unsupportedVersion(3)] { XCTAssertEqual(OpenOutcome(load), .unreadable) }
    }

    func testOpeningAPlaylistCreatesNoMainWindowOrPlaylistList() {                         // TC-45 / TC-96
        finderOpen(save(PlaylistFixture(), as: "P.lplaylist"))
        let titled = NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }
        XCTAssertEqual(titled.count, 1)
        XCTAssertTrue(titled[0].windowController is PlaylistWindowController)
    }
}
