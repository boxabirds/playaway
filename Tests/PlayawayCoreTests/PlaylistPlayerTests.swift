import XCTest
@testable import PlayawayCore

/// Integration of PlaylistPlayer with the real decider, shuffle, settings, classifier, gate, resolver, registry and
/// engine, over real fixture files and a recording sink. Rows follow the playlist-playback design (TC-19..TC-135).
final class PlaylistPlayerTests: XCTestCase {
    let names = Fixtures.trackNames

    // MARK: automatic advance

    func testPlaysAllTracksInListedOrderThenStops() {            // TC-19, prd.playlist.order/advance/repeat_off
        let rig = PlayerRig()
        rig.player.start()
        for _ in 0..<4 { rig.finishCurrent() }
        XCTAssertEqual(rig.startedNames, names)
        XCTAssertTrue(rig.player.isPlaying)
        rig.finishCurrent()
        XCTAssertEqual(rig.engine.state, .idle)
        XCTAssertFalse(rig.player.isPlaying)
        XCTAssertEqual(rig.startedNames.count, 5, "no sixth start")
    }

    func testRepeatAllStartsAgain() {                              // TC-20
        let rig = PlayerRig(repeatMode: .all)
        rig.player.start()
        for _ in 0..<5 { rig.finishCurrent() }
        XCTAssertEqual(rig.startedNames, names + ["track1.mp3"])
    }

    func testRepeatOneReplaysTheSameTrack() {                      // TC-21
        let rig = PlayerRig(repeatMode: .one)
        rig.player.start()
        rig.finishCurrent(); rig.finishCurrent()
        XCTAssertEqual(rig.startedNames, ["track1.mp3", "track1.mp3", "track1.mp3"])
    }

    func testShuffleOnPlaysEveryTrackOnceInSeededOrder() {         // TC-22 / TC-70
        let rig = PlayerRig(shuffle: true)
        let before = rig.fixture.playlist
        rig.player.start()
        for _ in 0..<4 { rig.finishCurrent() }
        rig.finishCurrent()
        XCTAssertEqual(Set(rig.startedNames), Set(names))
        XCTAssertEqual(rig.startedNames.count, 5)
        let expected = seededShuffler().pass(for: before, startingWith: nil).map { track in
            URL(fileURLWithPath: rig.fixture.urls[before.tracks.firstIndex(of: track)!].path).lastPathComponent }
        XCTAssertEqual(rig.startedNames, expected)
        XCTAssertEqual(rig.engine.state, .idle)
        XCTAssertEqual(rig.playlist, before, "shuffle does not rewrite the playlist")
    }

    func testOneTrackPlaylistRepeatModes() {                        // TC-76..78
        for (mode, plays) in [(RepeatMode.off, 1), (.all, 2), (.one, 2)] {
            let rig = PlayerRig(fixture: PlaylistFixture(trackNames: ["track1.mp3"]), repeatMode: mode)
            rig.player.start()
            rig.finishCurrent()
            XCTAssertEqual(rig.startedNames.count, plays, "\(mode)")
        }
    }

    // MARK: start cases

    func testEmptyPlaylistStartsNothingAndStopsNothing() {          // TC-74 / TC-80 / TC-83
        let rig = PlayerRig(fixture: PlaylistFixture(trackNames: []))
        let other = PlayerRig()
        other.engine.events.sink { _ in }.cancel()
        let sharedRegistry = ActiveSessionRegistry()
        let playing = rig.makePlayer(registry: sharedRegistry)
        _ = playing
        // another session is playing on the SAME engine/registry
        let busy = PlayerRig()
        busy.player.start()
        let empty = PlaylistPlayer(playlist: { Playlist() }, settings: busy.settings, engine: busy.engine,
                                   marks: busy.marks, registry: busy.registry)
        empty.start()
        XCTAssertTrue(busy.player.isPlaying, "the other session keeps playing untouched")
        XCTAssertFalse(empty.isPlaying)
        XCTAssertEqual(busy.startedNames, ["track1.mp3"])
    }

    func testStartingTakesOverFromAnotherPlaylist() {               // TC-84/85, prd.playlist.start
        let busy = PlayerRig()
        busy.player.start()
        let second = PlaylistFixture(trackNames: ["track3.mp3", "track4.mp3"])
        let newPlayer = PlaylistPlayer(playlist: { second.playlist }, settings: busy.settings,
                                       engine: busy.engine, marks: busy.marks, registry: busy.registry)
        newPlayer.start()
        XCTAssertFalse(busy.player.isPlaying, "the first playlist ended")
        XCTAssertTrue(newPlayer.isPlaying)
        XCTAssertEqual(busy.engine.currentURL?.lastPathComponent, "track3.mp3")
        busy.finishCurrent()
        XCTAssertEqual(busy.startedNames, ["track1.mp3", "track3.mp3", "track4.mp3"], "ended session no longer advances")
    }

    func testStartNeverWritesSettings() {                           // TC-102/131
        let defaults = isolatedDefaults()
        let settings = PlayModeSettings(store: PlayModeStore(defaults: defaults))
        let rig = PlayerRig()
        let player = PlaylistPlayer(playlist: { rig.playlist }, settings: settings, engine: rig.engine,
                                    marks: rig.marks, registry: rig.registry)
        player.start()
        player.play(track: rig.playlist.tracks[2])
        XCTAssertTrue(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("shuffle") || $0.hasPrefix("repeat") }.isEmpty)
    }

    // MARK: double-click on a track

    func testDoubleClickPlaysTrackThenCarriesOnInListedOrder() {    // TC-110
        let rig = PlayerRig()
        rig.player.play(track: rig.playlist.tracks[2])
        XCTAssertEqual(rig.startedNames, ["track3.mp3"])
        XCTAssertEqual(rig.engine.position, 0)
        rig.finishCurrent()
        XCTAssertEqual(rig.startedNames, ["track3.mp3", "track4.mp3"])
    }

    func testDoubleClickWithShuffleFollowsWithTheRemainingTracksOnce() {    // TC-119 / prd.playlist.play_track_shuffle
        let rig = PlayerRig(shuffle: true)
        let chosen = rig.playlist.tracks[2]
        rig.player.play(track: chosen)
        for _ in 0..<4 { rig.finishCurrent() }
        XCTAssertEqual(rig.startedNames.first, "track3.mp3")
        XCTAssertEqual(Set(rig.startedNames), Set(names))
        XCTAssertEqual(rig.startedNames.count, 5)
        let expected = seededShuffler().pass(for: rig.playlist, startingWith: chosen)
        XCTAssertEqual(rig.startedNames, expected.map { track in
            rig.fixture.urls[rig.playlist.tracks.firstIndex(of: track)!].lastPathComponent })
    }

    func testDoubleClickOnTrackOfThisPlaylistWhilePlayingReplaces() {   // TC-113 / TC-122
        for shuffle in [false, true] {
            let rig = PlayerRig(shuffle: shuffle)
            rig.player.start()
            rig.player.play(track: rig.playlist.tracks[2])
            XCTAssertEqual(rig.currentName, "track3.mp3")
            XCTAssertEqual(rig.backend.playing?.url.lastPathComponent, "track3.mp3")
            XCTAssertEqual(rig.backend.players.filter(\.running).count, 1)
        }
    }

    func testDoubleClickOnTrackOfAnotherPlaylistEndsTheOtherOnce() {    // TC-116
        let rig = PlayerRig()
        rig.player.start()
        final class CountingSession: SessionEnding { var ended = 0; func end() { ended += 1 } }
        let spy = CountingSession()
        rig.registry.begin(spy)                  // another playlist is the active session
        rig.player.play(track: rig.playlist.tracks[1])
        XCTAssertEqual(spy.ended, 1)
        XCTAssertEqual(rig.currentName, "track2.mp3")
    }

    func testDoubleClickOnMissingTrackLeavesPlaybackAndMarksIt() {      // TC-111/114/117, TC-130
        for otherPlaying in [false, true] {
            let rig = PlayerRig()
            if otherPlaying { rig.player.start() }
            rig.fixture.deleteFile(at: 2)
            let startsBefore = rig.startedNames
            rig.player.play(track: rig.playlist.tracks[2])
            XCTAssertEqual(rig.marks.mark(of: rig.playlist.tracks[2]), .unreadable)
            XCTAssertEqual(rig.startedNames, startsBefore, "engine never called for it")
            XCTAssertEqual(rig.engine.isPlaying, otherPlaying, "anything playing carries on unchanged")
            if otherPlaying { XCTAssertTrue(rig.player.isSessionActive) }
        }
    }

    func testDoubleClickOnUnreadableTrackIsMarkedNotPlayed() throws {   // TC-112 / TC-65
        let rig = PlayerRig()
        let unreadable = rig.fixture.urls[1]
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path) }
        rig.player.play(track: rig.playlist.tracks[1])
        XCTAssertEqual(rig.marks.mark(of: rig.playlist.tracks[1]), .unreadable)
        XCTAssertTrue(rig.startedNames.isEmpty)
        XCTAssertFalse(rig.engine.isPlaying)
    }

    func testDoubleClickWhereEngineFailsMarksTheTrackAndStopsSession() {   // TC-132
        let rig = PlayerRig()
        rig.backend.unreadableNames = ["track2.mp3"]
        rig.player.play(track: rig.playlist.tracks[1])
        XCTAssertEqual(rig.marks.mark(of: rig.playlist.tracks[1]), .unreadable)
        XCTAssertFalse(rig.player.isPlaying)
    }

    func testNoOutputDeviceMarksNothingAndStopsSession() {          // TC-66 / TC-133 / TC-75
        let rig = PlayerRig(hasDevice: false)
        rig.player.start()
        XCTAssertFalse(rig.player.isPlaying)
        XCTAssertFalse(rig.player.isSessionActive)
        for track in rig.playlist.tracks { XCTAssertEqual(rig.marks.mark(of: track), .readable) }
        rig.player.play(track: rig.playlist.tracks[0])
        XCTAssertEqual(rig.marks.mark(of: rig.playlist.tracks[0]), .readable)
    }

    func testTrackNotInThisPlaylistIsIgnored() {
        let rig = PlayerRig()
        rig.player.play(track: bareTracks(1)[0])
        XCTAssertTrue(rig.startedNames.isEmpty)
    }

    // MARK: unreadable and missing tracks during play-through

    func testUnreadableTrackIsSkippedAndMarked() {                  // TC-60
        let rig = PlayerRig()
        rig.backend.unreadableNames = ["track3.mp3"]
        rig.player.start()
        rig.finishCurrent(); rig.finishCurrent()
        XCTAssertEqual(rig.startedNames, ["track1.mp3", "track2.mp3", "track4.mp3"])
        XCTAssertEqual(rig.marks.mark(of: rig.playlist.tracks[2]), .unreadable)
        XCTAssertEqual(rig.marks.mark(of: rig.playlist.tracks[3]), .readable)
    }

    func testUnreadableAtStartLastAndOnly() {                       // TC-61..64
        var rig = PlayerRig()
        rig.backend.unreadableNames = ["track1.mp3"]
        rig.player.start()
        XCTAssertEqual(rig.startedNames, ["track2.mp3"], "TC-62")

        rig = PlayerRig()
        rig.backend.unreadableNames = ["track5.mp3"]
        rig.player.start()
        for _ in 0..<3 { rig.finishCurrent() }
        rig.finishCurrent()
        XCTAssertEqual(rig.marks.mark(of: rig.playlist.tracks[4]), .unreadable, "TC-61")
        XCTAssertFalse(rig.player.isSessionActive)

        rig = PlayerRig(fixture: PlaylistFixture(trackNames: ["track1.mp3"]))
        rig.backend.unreadableNames = ["track1.mp3"]
        rig.player.start()
        XCTAssertEqual(rig.marks.mark(of: rig.playlist.tracks[0]), .unreadable, "TC-63")
        XCTAssertFalse(rig.player.isSessionActive)

        rig = PlayerRig()
        rig.backend.unreadableNames = ["track2.mp3", "track3.mp3"]
        rig.player.start()
        rig.finishCurrent()
        XCTAssertEqual(rig.startedNames, ["track1.mp3", "track4.mp3"], "TC-64")
        XCTAssertEqual(rig.marks.mark(of: rig.playlist.tracks[1]), .unreadable)
        XCTAssertEqual(rig.marks.mark(of: rig.playlist.tracks[2]), .unreadable)
    }

    func testMissingTrackSkippedAndMarkedBeforeEngineIsCalled() {   // TC-92 / TC-99
        let rig = PlayerRig()
        rig.fixture.deleteFile(at: 2)
        rig.player.start()
        rig.finishCurrent(); rig.finishCurrent()
        XCTAssertEqual(rig.startedNames, ["track1.mp3", "track2.mp3", "track4.mp3"])
        XCTAssertEqual(rig.marks.mark(of: rig.playlist.tracks[2]), .unreadable)
        XCTAssertFalse(rig.backend.log.contains { $0.contains("track3.mp3") }, "engine receives no play for it")
    }

    func testMissingFirstLastAndRepeatAll() {                       // TC-93/94/97
        var rig = PlayerRig()
        rig.fixture.deleteFile(at: 0)
        rig.player.start()
        XCTAssertEqual(rig.startedNames, ["track2.mp3"], "TC-94")
        XCTAssertEqual(rig.marks.mark(of: rig.playlist.tracks[0]), .unreadable)

        rig = PlayerRig()
        rig.fixture.deleteFile(at: 4)
        rig.player.start()
        for _ in 0..<4 { rig.finishCurrent() }
        XCTAssertFalse(rig.player.isSessionActive, "TC-93: session stops after track 4")
        XCTAssertEqual(rig.marks.mark(of: rig.playlist.tracks[4]), .unreadable)

        rig = PlayerRig(repeatMode: .all)
        rig.fixture.deleteFile(at: 4)
        rig.player.start()
        for _ in 0..<4 { rig.finishCurrent() }
        XCTAssertEqual(rig.startedNames.last, "track1.mp3", "TC-97/TC-21(5): wraps and never plays track 5")
        XCTAssertFalse(rig.startedNames.dropLast().contains("track5.mp3"))
    }

    func testAllMissingMarksEachAndStopsEvenWithRepeat() {         // TC-95 / story 5 TC-24/25
        for mode in [RepeatMode.off, .all] {
            let rig = PlayerRig(repeatMode: mode)
            for index in 0..<5 { rig.fixture.deleteFile(at: index) }
            rig.player.start()
            XCTAssertTrue(rig.backend.players.isEmpty, "engine never called")
            for track in rig.playlist.tracks { XCTAssertEqual(rig.marks.mark(of: track), .unreadable) }
            XCTAssertFalse(rig.player.isSessionActive, "no tight loop (repeat \(mode))")
        }
    }

    func testMissingAndUnreadableMixed() {                          // TC-96
        let rig = PlayerRig()
        rig.fixture.deleteFile(at: 1)
        rig.backend.unreadableNames = ["track3.mp3"]
        rig.player.start()
        rig.finishCurrent()
        XCTAssertEqual(rig.startedNames, ["track1.mp3", "track4.mp3"])
    }

    func testShuffleWithOneMissingTrackPlaysTheOtherFourOnce() {   // TC-98
        let rig = PlayerRig(shuffle: true)
        rig.fixture.deleteFile(at: 1)
        rig.player.start()
        for _ in 0..<4 { rig.finishCurrent() }
        XCTAssertEqual(Set(rig.startedNames), Set(names).subtracting(["track2.mp3"]))
        XCTAssertEqual(rig.startedNames.count, 4)
        XCTAssertEqual(rig.marks.mark(of: rig.playlist.tracks[1]), .unreadable)
    }

    func testFileThatReappearsPlaysOnTheNextPass() {                // TC-100
        let rig = PlayerRig(repeatMode: .all)
        let url = rig.fixture.urls[2]
        let contents = try! Data(contentsOf: url)
        rig.fixture.deleteFile(at: 2)                               // a real delete: a moved file would be followed
        rig.player.start()
        for _ in 0..<3 { rig.finishCurrent() }                      // 1 → 2 → (3 skipped) 4 → 5
        XCTAssertFalse(rig.startedNames.contains("track3.mp3"))
        try! contents.write(to: url)                                // the file is back at the same path
        rig.finishCurrent()                                         // 5 ends, wraps to 1
        rig.finishCurrent(); rig.finishCurrent()                    // 1 → 2 → 3
        XCTAssertEqual(rig.startedNames.last, "track3.mp3", "status is re-read every time")
    }

    func testMarkIsNotWrittenToThePlaylistAndNoSettingsChange() {  // TC-101
        let rig = PlayerRig()
        rig.fixture.deleteFile(at: 1)
        let before = rig.playlist
        rig.player.start(); rig.finishCurrent()
        XCTAssertEqual(rig.playlist, before)
    }

    // MARK: changing modes while playing

    func testTurningShuffleOnKeepsTrackAndShufflesTheRest() {       // TC-38 / TC-39
        let rig = PlayerRig()
        rig.player.play(track: rig.playlist.tracks[2])
        let playsBefore = rig.backend.log.count
        rig.settings.toggleShuffle()
        rig.settings.cycleRepeat()
        XCTAssertEqual(rig.backend.log.count, playsBefore, "the track keeps playing, no restart")
        XCTAssertEqual(rig.engine.position, 0)
        for _ in 0..<4 { rig.finishCurrent() }
        let expected = seededShuffler().pass(for: rig.playlist, startingWith: rig.playlist.tracks[2])
        XCTAssertEqual(rig.startedNames, expected.map { rig.fixture.urls[rig.playlist.tracks.firstIndex(of: $0)!].lastPathComponent })
    }

    func testTurningShuffleOffContinuesInListedOrderFromCurrent() {   // TC-40
        let rig = PlayerRig(shuffle: true)
        rig.player.play(track: rig.playlist.tracks[2])
        rig.settings.toggleShuffle()
        rig.finishCurrent()
        XCTAssertEqual(rig.startedNames, ["track3.mp3", "track4.mp3"])
    }

    // MARK: next and previous (story 11 rows through the real player)

    func testNextAndPrevious() {                                    // TC-37, E2E-3
        let rig = PlayerRig()
        rig.player.play(track: rig.playlist.tracks[2])
        rig.player.next()
        XCTAssertEqual(rig.currentName, "track4.mp3")
        XCTAssertEqual(rig.backend.log.filter { $0 == "stop:track3.mp3" }.count, 1, "track 3 stopped")
        rig.player.previous()
        XCTAssertEqual(rig.currentName, "track3.mp3")
    }

    func testNextWithRepeatOneMovesOn() {                           // TC-25
        let rig = PlayerRig(repeatMode: .one)
        rig.player.play(track: rig.playlist.tracks[2])
        rig.player.next()
        XCTAssertEqual(rig.currentName, "track4.mp3")
    }

    func testNextOnLastTrackEndsOrWraps() {                         // TC-29 / TC-30 / TC-87
        var rig = PlayerRig()
        rig.player.play(track: rig.playlist.tracks[4])
        rig.player.next()
        XCTAssertEqual(rig.engine.state, .idle)
        XCTAssertEqual(rig.startedNames, ["track5.mp3"], "must not restart the playlist")
        rig = PlayerRig(repeatMode: .all)
        rig.player.play(track: rig.playlist.tracks[4])
        rig.player.next()
        XCTAssertEqual(rig.currentName, "track1.mp3")
    }

    func testPreviousOnFirstTrack() {                               // TC-27 / TC-28 / TC-90
        var rig = PlayerRig()
        rig.player.play(track: rig.playlist.tracks[0])
        rig.player.previous()
        XCTAssertEqual(rig.currentName, "track1.mp3", "repeat off: nothing happens")
        XCTAssertEqual(rig.startedNames, ["track1.mp3"])
        XCTAssertTrue(rig.engine.isPlaying)
        for mode in [RepeatMode.all, .one] {
            rig = PlayerRig(repeatMode: mode)
            rig.player.play(track: rig.playlist.tracks[0])
            rig.player.previous()
            XCTAssertEqual(rig.currentName, "track5.mp3", "repeat \(mode): the last track plays (TC-97)")
            XCTAssertEqual(rig.engine.position, 0)
        }
    }

    func testPreviousWithShuffleStepsBackThroughThePass() {         // TC-33 / TC-92..94
        let rig = PlayerRig(shuffle: true)
        rig.player.start()
        rig.player.next(); rig.player.next()
        let beforeBack = rig.startedNames
        rig.player.previous()
        XCTAssertEqual(rig.currentName, beforeBack[1], "the second track of the pass plays")
    }

    func testNextAndPreviousIgnoredWithoutASession() {              // TC-20/21/85
        let rig = PlayerRig()
        rig.player.next(); rig.player.previous()
        XCTAssertTrue(rig.backend.log.isEmpty)
    }

    func testNextSkipsUnreadableTrack() {                           // TC-38
        let rig = PlayerRig()
        rig.backend.unreadableNames = ["track4.mp3"]
        rig.player.play(track: rig.playlist.tracks[2])
        rig.player.next()
        XCTAssertEqual(rig.currentName, "track5.mp3")
        XCTAssertEqual(rig.marks.mark(of: rig.playlist.tracks[3]), .unreadable)
    }

    func testPreviousRestoresCurrentWhenNothingPlayableBefore() {
        let rig = PlayerRig()
        rig.backend.unreadableNames = ["track1.mp3"]
        rig.player.play(track: rig.playlist.tracks[1])
        rig.player.previous()
        XCTAssertEqual(rig.currentName, "track2.mp3", "nothing playable before it: playback unchanged")
        XCTAssertEqual(rig.player.current, rig.playlist.tracks[1])
    }

    // MARK: stop and ended sessions

    func testStopEndsTheSessionSoNextDoesNothing() {
        let rig = PlayerRig()
        rig.player.start()
        rig.engine.stop()
        XCTAssertFalse(rig.player.isSessionActive)
        rig.player.next()
        XCTAssertEqual(rig.startedNames, ["track1.mp3"])
    }

    func testEndedSessionDoesNotAdvance() {
        let rig = PlayerRig()
        rig.player.start()
        rig.player.end()
        rig.finishCurrent()
        XCTAssertEqual(rig.startedNames, ["track1.mp3"])
        XCTAssertFalse(rig.player.isPlaying)
    }

    func testPauseKeepsSessionPlaying() {
        let rig = PlayerRig()
        rig.player.start()
        rig.engine.pause()
        XCTAssertTrue(rig.player.isPlaying, "paused still counts as the playing playlist")
    }

    func testRegistryEndsPreviousExactlyOnce() {                    // TC-103
        final class Spy: SessionEnding { var ended = 0; func end() { ended += 1 } }
        let registry = ActiveSessionRegistry()
        let a = Spy(), b = Spy()
        registry.begin(a)
        registry.begin(b)
        registry.begin(b)
        XCTAssertEqual(a.ended, 1)
        XCTAssertEqual(b.ended, 0)
        registry.endActive()
        XCTAssertEqual(b.ended, 1)
    }

    func testClearingMark() {
        let store = ReadabilityMarkStore()
        let track = bareTracks(1)[0]
        store.clearMark(of: track)
        XCTAssertEqual(store.mark(of: track), .readable)
        store.markUnreadable(track)
        XCTAssertEqual(store.mark(of: track), .unreadable)
        store.clearMark(of: track)
        XCTAssertEqual(store.mark(of: track), .readable)
    }

    // MARK: load paused at a remembered place

    func testLoadShowsTheSongPausedAtTheRememberedPlaceAndMakesNoSound() {
        let rig = PlayerRig()
        let track = rig.fixture.tracks[2]
        XCTAssertTrue(rig.player.load(track: track, atSeconds: 1.5))
        XCTAssertEqual(rig.engine.state, .paused)
        XCTAssertEqual(rig.currentName, "track3.mp3")
        XCTAssertEqual(rig.engine.position, 1.5)
        XCTAssertEqual(rig.engine.duration, rig.backend.defaultDuration, "the length is known, as for any paused song")
        XCTAssertEqual(rig.player.current, track)
        XCTAssertTrue(rig.startedNames.isEmpty, "nothing was started")
    }

    func testPlayAfterALoadCarriesOnFromThatPlace() {
        let rig = PlayerRig()
        rig.player.load(track: rig.fixture.tracks[0], atSeconds: 2)
        rig.engine.resume()
        XCTAssertEqual(rig.engine.state, .playing)
        XCTAssertEqual(rig.engine.position, 2)
    }

    func testLoadBeyondTheEndClampsToTheEndOfTheSong() {
        let rig = PlayerRig()
        XCTAssertTrue(rig.player.load(track: rig.fixture.tracks[0], atSeconds: 100_000))
        XCTAssertEqual(rig.engine.position, rig.backend.defaultDuration)
    }

    func testLoadOfASongThatIsGoneChangesNothing() {
        let rig = PlayerRig()
        rig.fixture.deleteFile(at: 1)
        XCTAssertFalse(rig.player.load(track: rig.fixture.tracks[1], atSeconds: 1))
        XCTAssertEqual(rig.engine.state, .idle)
        XCTAssertNil(rig.player.current)
    }
}
