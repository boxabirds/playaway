import XCTest
import AppKit
@testable import LocalPlayer

/// Regressions found by the review of the code against spec/. Each test failed before its fix.

// MARK: - Player and decider level (no app needed)

final class ReviewFixPlayerTests: XCTestCase {
    final class CountingSession: SessionEnding { var ended = 0; func end() { ended += 1 } }

    /// Spec 002: a track that cannot be played leaves anything already playing unchanged.
    func testDoubleClickOnTrackTheEngineRefusesLeavesPlaybackAndSessionUnchanged() {
        let rig = PlayerRig()
        rig.player.start()
        rig.backend.unreadableNames = ["track5.mp3"]
        rig.player.play(track: rig.playlist.tracks[4])
        XCTAssertEqual(rig.marks.mark(of: rig.playlist.tracks[4]), .unreadable)
        XCTAssertTrue(rig.engine.isPlaying, "the music is not silenced")
        XCTAssertEqual(rig.currentName, "track1.mp3")
        XCTAssertTrue(rig.player.isSessionActive)
        rig.finishCurrent()
        XCTAssertEqual(rig.startedNames, ["track1.mp3", "track2.mp3"], "the session still advances")
    }

    func testDoubleClickOnTrackTheEngineRefusesDoesNotEndAnotherPlaylistsSession() {
        let rig = PlayerRig()
        let other = CountingSession()
        rig.registry.begin(other)
        rig.backend.unreadableNames = ["track2.mp3"]
        rig.player.play(track: rig.playlist.tracks[1])
        XCTAssertEqual(other.ended, 0)
        XCTAssertTrue(rig.registry.active === other)
    }

    func testDoubleClickWithNoOutputDeviceLeavesTheActiveSessionAlone() {
        let rig = PlayerRig(hasDevice: false)
        let other = CountingSession()
        rig.registry.begin(other)
        rig.player.play(track: rig.playlist.tracks[1])
        XCTAssertEqual(other.ended, 0)
    }

    func testRemovingThePlayingTrackCarriesOnWithTheTrackAfterIt() {
        let rig = PlayerRig()
        rig.player.start()
        rig.finishCurrent()                                   // track 2 of 5 playing
        rig.playlist.tracks.remove(at: 1)
        rig.finishCurrent()
        XCTAssertEqual(rig.startedNames, ["track1.mp3", "track2.mp3", "track3.mp3"])
        XCTAssertTrue(rig.player.isSessionActive)
    }

    func testRemovingThePlayingTrackThenNextPlaysTheTrackAfterIt() {
        let rig = PlayerRig()
        rig.player.start()
        rig.player.next()                                     // track 2
        rig.playlist.tracks.remove(at: 1)
        rig.player.next()
        XCTAssertEqual(rig.currentName, "track3.mp3")
    }

    func testRemovingThePlayingTrackThenPreviousPlaysTheTrackBeforeIt() {
        let rig = PlayerRig()
        rig.player.start()
        rig.player.next()
        rig.playlist.tracks.remove(at: 1)
        rig.player.previous()
        XCTAssertEqual(rig.currentName, "track1.mp3")
    }

    func testRemovingTheLastPlayingTrackEndsOrWrapsPerRepeat() {
        for (mode, wraps) in [(RepeatMode.off, false), (.all, true)] {
            let rig = PlayerRig(repeatMode: mode)
            rig.player.start()
            for _ in 0..<4 { rig.finishCurrent() }            // track 5 of 5
            rig.playlist.tracks.remove(at: 4)
            rig.finishCurrent()
            XCTAssertEqual(rig.player.isPlaying, wraps, "\(mode)")
            if wraps { XCTAssertEqual(rig.currentName, "track1.mp3") }
        }
    }

    func testRemovingThePlayingTrackWithShuffleContinuesTheSamePass() {
        let rig = PlayerRig(shuffle: true)
        let before = rig.playlist
        let pass = seededShuffler().pass(for: before, startingWith: nil)
        rig.player.start()
        let playing = rig.playlist.tracks.firstIndex(of: pass[0])!
        rig.playlist.tracks.remove(at: playing)
        rig.finishCurrent()
        let expected = rig.fixture.urls[before.tracks.firstIndex(of: pass[1])!].lastPathComponent
        XCTAssertEqual(rig.currentName, expected)
    }
}

final class ReviewFixOpenTests: XCTestCase {
    /// A single file that fails to play must leave the playlist session and its audio exactly as they were.
    func testOpeningAFileTheEngineRefusesLeavesThePlaylistSessionRunning() {
        let rig = PlayerRig()
        let notices = RecordingNotices()
        let router = SessionOnlyOpener(registry: rig.registry)
        let coordinator = OpenCoordinator(classifier: FormatClassifier(), engine: rig.engine, notices: notices,
                                          playlists: router)
        rig.player.start()
        rig.backend.unreadableNames = ["tone.wav"]
        XCTAssertEqual(coordinator.open(Fixtures.url("tone.wav")), .played(.failed("unreadable")))
        XCTAssertTrue(rig.player.isSessionActive)
        XCTAssertEqual(rig.currentName, "track1.mp3")
        rig.finishCurrent()
        XCTAssertEqual(rig.startedNames, ["track1.mp3", "track2.mp3"], "Next and advance still work")
    }

    func testOpeningAPlayableFileStillEndsThePlaylistSession() {
        let rig = PlayerRig()
        let coordinator = OpenCoordinator(classifier: FormatClassifier(), engine: rig.engine, notices: RecordingNotices(),
                                          playlists: SessionOnlyOpener(registry: rig.registry))
        rig.player.start()
        coordinator.open(Fixtures.url("tone.wav"))
        XCTAssertFalse(rig.player.isSessionActive)
        XCTAssertEqual(rig.currentName, "tone.wav")
    }

    final class SessionOnlyOpener: PlaylistOpening {
        let registry: ActiveSessionRegistry
        init(registry: ActiveSessionRegistry) { self.registry = registry }
        func canOpen(_ url: URL) -> Bool { false }
        func open(_ url: URL) {}
        func endActivePlayback() { registry.endActive() }
    }
}

// MARK: - Document level, UI route and script route

@MainActor
final class ReviewFixDocumentTests: XCTestCase {
    var app: TestApp!
    let dir = TempDir("reviewfix")
    override func setUp() async throws { app = TestApp() }
    override func tearDown() async throws { app.tearDown() }

    func resolve(_ doc: PlaylistDocument) {
        var done = false
        doc.resolveStatuses { done = true }
        spin { done }
    }

    // Finding: case-only rename refused as name taken.

    func testCaseOnlyRenameSucceedsFromTheUI() throws {
        let doc = app.openSaved(PlaylistFixture(trackNames: ["track1.mp3"]).playlist, at: dir.path("dinner.lplaylist"))
        var result: Result<Void, PlaylistDocument.RenameError>?
        doc.renameFile(to: "Dinner") { result = $0 }
        spin { result != nil }
        XCTAssertNoThrow(try result?.get())
        XCTAssertEqual(doc.fileURL?.lastPathComponent, "Dinner.lplaylist")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.url.path), ["Dinner.lplaylist"])
    }

    func testCaseOnlyRenameSucceedsFromTheScript() throws {
        let actions = AppActions(services: app.services)
        actions.isReady = { true }
        let doc = app.openSaved(PlaylistFixture(trackNames: ["track1.mp3"]).playlist, at: dir.path("dinner.lplaylist"))
        XCTAssertNoThrow(try actions.renamePlaylist("dinner", to: "Dinner"))
        XCTAssertEqual(doc.fileURL?.lastPathComponent, "Dinner.lplaylist")
    }

    func testRenameToADifferentExistingFileIsStillRefused() {
        let doc = app.openSaved(Playlist(), at: dir.path("dinner.lplaylist"))
        try! Data().write(to: dir.path("Supper.lplaylist"))
        var result: Result<Void, PlaylistDocument.RenameError>?
        doc.renameFile(to: "Supper") { result = $0 }
        spin { result != nil }
        XCTAssertThrowsError(try result?.get())
        XCTAssertEqual(doc.fileURL?.lastPathComponent, "dinner.lplaylist")
    }

    // Finding: the launch resolve overwrote a Locate done while it ran.

    func testLocateDuringABackgroundResolveIsNotUndoneByIt() {
        let fixture = PlaylistFixture()
        let doc = app.openSaved(fixture.playlist, at: dir.path("Race.lplaylist"))
        let newHome = TempDir("newhome")
        newHome.copyFixture("track2.mp3")
        fixture.deleteFile(at: 1)
        resolve(doc)
        XCTAssertEqual(doc.statuses.status(of: fixture.tracks[1].id), .missing)

        var done = false
        doc.resolveStatuses { done = true }                   // snapshot taken: track 2 still missing
        let window = app.window(of: doc)
        window.chooseFileToLocate = { newHome.path("track2.mp3") }
        let item = NSMenuItem(); item.representedObject = fixture.tracks[1].id
        window.locateTrack(item)                              // lands before the background result is applied
        spin { done }

        XCTAssertEqual(doc.statuses.status(of: fixture.tracks[1].id), .resolved(newHome.path("track2.mp3")))
        XCTAssertNotEqual(doc.playlist.tracks[1].reference, fixture.tracks[1].reference, "the located reference stays")
        XCTAssertEqual(doc.playlist.tracks[1].reference.fileName, "track2.mp3")
        XCTAssertEqual(doc.playlist.tracks[1].reference.lastKnownPath, newHome.path("track2.mp3").canonicalPath)
    }

    // Finding: undo restored an older missing reference over a relink.

    func testUndoOfAnEarlierEditKeepsALaterLocate() throws {
        let fixture = PlaylistFixture()
        let doc = app.openSaved(fixture.playlist, at: dir.path("Undo.lplaylist"))
        let newHome = TempDir("newhome")
        newHome.copyFixture("track2.mp3")
        fixture.deleteFile(at: 1)
        resolve(doc)
        doc.undoManager?.removeAllActions()

        try doc.removeTracks(at: [4])
        let window = app.window(of: doc)
        window.chooseFileToLocate = { newHome.path("track2.mp3") }
        let item = NSMenuItem(); item.representedObject = fixture.tracks[1].id
        window.locateTrack(item)
        let located = doc.playlist.tracks[1].reference

        doc.undoManager?.undo()
        XCTAssertEqual(doc.playlist.tracks.count, 5, "the removed row is back")
        XCTAssertEqual(doc.playlist.tracks[1].reference, located, "undo does not revert the relink")
        XCTAssertEqual(doc.statuses.status(of: fixture.tracks[1].id), .resolved(newHome.path("track2.mp3")))

        doc.undoManager?.redo()
        XCTAssertEqual(doc.playlist.tracks.count, 4)
        XCTAssertEqual(doc.playlist.tracks[1].reference, located, "redo does not revert it either")
    }

    // Finding: removing the playing track stopped the playlist (UI route and script route).

    func testRemovingThePlayingRowCarriesOnFromTheUI() {
        let fixture = PlaylistFixture(trackNames: ["track1.mp3", "track2.mp3", "track3.mp3"])
        let doc = app.openSaved(fixture.playlist, at: dir.path("Live.lplaylist"))
        doc.player.start()
        doc.player.next()                                     // track 2
        let window = app.window(of: doc)
        window.tableView.selectRowIndexes([1], byExtendingSelection: false)
        window.deleteBackward(nil)
        app.backend.playing?.finish()
        XCTAssertEqual(app.services.engine.currentURL?.lastPathComponent, "track3.mp3")
    }

    func testRemovingThePlayingTrackCarriesOnFromTheScript() throws {
        let actions = AppActions(services: app.services)
        actions.isReady = { true }
        let fixture = PlaylistFixture(trackNames: ["track1.mp3", "track2.mp3", "track3.mp3"])
        _ = app.openSaved(fixture.playlist, at: dir.path("Live.lplaylist"))
        try actions.playTrack(2, inPlaylist: "Live")
        try actions.removeTrack(2, fromPlaylist: "Live")
        app.backend.playing?.finish()
        XCTAssertEqual(app.services.engine.currentURL?.lastPathComponent, "track3.mp3")
    }

    // Finding: a refused double-click silenced the music (UI route and script route).

    func testRefusedRowDoubleClickLeavesPlaybackAloneFromTheUI() {
        let fixture = PlaylistFixture(trackNames: ["track1.mp3", "track2.mp3"])
        let doc = app.openSaved(fixture.playlist, at: dir.path("A.lplaylist"))
        doc.player.start()
        app.backend.unreadableNames = ["track2.mp3"]
        app.window(of: doc).playRow(1)
        XCTAssertEqual(app.services.engine.currentURL?.lastPathComponent, "track1.mp3")
        XCTAssertTrue(app.services.engine.isPlaying)
    }

    func testRefusedPlayTrackLeavesPlaybackAloneFromTheScript() throws {
        let actions = AppActions(services: app.services)
        actions.isReady = { true }
        let fixture = PlaylistFixture(trackNames: ["track1.mp3", "track2.mp3"])
        _ = app.openSaved(fixture.playlist, at: dir.path("A.lplaylist"))
        try actions.playTrack(1, inPlaylist: "A")
        app.backend.unreadableNames = ["track2.mp3"]
        _ = try? actions.playTrack(2, inPlaylist: "A")
        XCTAssertEqual(app.services.engine.currentURL?.lastPathComponent, "track1.mp3")
        XCTAssertTrue(app.services.engine.isPlaying)
    }

    // Decided: closing the window of a playing playlist stops playback.

    func testClosingThePlayingPlaylistStopsPlayback() {
        let fixture = PlaylistFixture(trackNames: ["track1.mp3", "track2.mp3"])
        let doc = app.openSaved(fixture.playlist, at: dir.path("Close.lplaylist"))
        doc.player.start()
        XCTAssertTrue(app.services.engine.isPlaying)
        app.window(of: doc).close()
        XCTAssertEqual(app.services.engine.state, .idle)
        XCTAssertNil(app.services.registry.active)
    }

    func testClosingThroughTheDocumentStopsPlaybackToo() {
        let fixture = PlaylistFixture(trackNames: ["track1.mp3"])
        let doc = app.openSaved(fixture.playlist, at: dir.path("Close.lplaylist"))
        doc.player.start()
        doc.close()
        XCTAssertEqual(app.services.engine.state, .idle)
    }

    func testClosingAPlaylistThatIsNotPlayingLeavesOtherAudioAlone() {
        let first = PlaylistFixture(trackNames: ["track1.mp3"]), second = PlaylistFixture(trackNames: ["track2.mp3"])
        let playing = app.openSaved(first.playlist, at: dir.path("Playing.lplaylist"))
        let idle = app.openSaved(second.playlist, at: dir.path("Idle.lplaylist"))
        playing.player.start()
        idle.close()
        XCTAssertTrue(app.services.engine.isPlaying)
        XCTAssertTrue(playing.player.isSessionActive)
    }

    func testClosingAPlaylistLeavesAPlainFileThatIsPlayingAlone() {
        let doc = app.openSaved(Playlist(), at: dir.path("Idle.lplaylist"))
        _ = app.services.engine.play(Fixtures.url("tone.wav"))
        doc.close()
        XCTAssertTrue(app.services.engine.isPlaying)
    }
}
