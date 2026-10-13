import XCTest
@testable import PlayawayCore

private final class CountingStore: PlayModeStoring {
    var saves = 0
    func load() -> (shuffle: Bool, repeatMode: RepeatMode) { (true, .off) }
    func saveShuffle(_ on: Bool) { saves += 1 }
    func saveRepeat(_ mode: RepeatMode) { saves += 1 }
}

final class StartDecisionTests: XCTestCase {
    private var rng = SeededGenerator(seed: 11)

    func testSongUnderWayTogglesWhateverShuffleSays() {
        for shuffle in [true, false] {
            for playing in [true, false] {
                XCTAssertEqual(startDecision(session: .songUnderWay(isPlaying: playing), shuffleOn: shuffle, songCount: 5, random: &rng),
                               .toggleCurrentSong)
            }
        }
    }

    func testNoSongUnderWayWithShuffleOnStartsShuffledFromARandomSongOfThePlaylist() {
        var seen = Set<Int>()
        for _ in 0..<200 {
            guard case .startShuffled(let first) = startDecision(session: .noSongUnderWay, shuffleOn: true, songCount: 5, random: &rng)
            else { return XCTFail("expected a shuffled start") }
            XCTAssertTrue((0..<5).contains(first)); seen.insert(first)
        }
        XCTAssertEqual(seen, Set(0..<5), "every song can be chosen")
    }

    func testNoSongUnderWayWithShuffleOffStartsInOrder() {
        XCTAssertEqual(startDecision(session: .noSongUnderWay, shuffleOn: false, songCount: 5, random: &rng), .startInOrder)
    }

    func testEmptyPlaylistStartsNothing() {
        XCTAssertEqual(startDecision(session: .noSongUnderWay, shuffleOn: true, songCount: 0, random: &rng), .nothingToStart)
        XCTAssertEqual(startDecision(session: .noSongUnderWay, shuffleOn: false, songCount: 0, random: &rng), .nothingToStart)
    }

    func testIconIsPauseOnlyWhileThisPlaylistsSongPlays() {
        XCTAssertEqual(startButtonIcon(session: .songUnderWay(isPlaying: true)), .pause)
        XCTAssertEqual(startButtonIcon(session: .songUnderWay(isPlaying: false)), .play)
        XCTAssertEqual(startButtonIcon(session: .noSongUnderWay), .play)
    }

    /// A shuffled start plays a permutation of this playlist's songs only, and leaves the stored order alone.
    func testShuffledStartOrderIsAPermutationOfThisPlaylistAndStoredOrderIsUnchanged() {
        let tracks = bareTracks(5); let playlist = Playlist(tracks: tracks)
        guard case .startShuffled(let first) = startDecision(session: .noSongUnderWay, shuffleOn: true, songCount: tracks.count, random: &rng)
        else { return XCTFail() }
        let pass = seededShuffler().pass(for: playlist, startingWith: tracks[first])
        XCTAssertEqual(pass.first, tracks[first])
        XCTAssertEqual(Set(pass.map(\.id)), Set(tracks.map(\.id))); XCTAssertEqual(pass.count, 5)
        XCTAssertEqual(playlist.tracks, tracks)
    }

    /// The decision only reads the toggle: deciding never writes the stored Shuffle mode.
    func testDecidingNeverChangesOrSavesTheShuffleToggle() {
        let store = CountingStore(); let settings = PlayModeSettings(store: store)
        for session in [PlaylistSessionState.noSongUnderWay, .songUnderWay(isPlaying: true), .songUnderWay(isPlaying: false)] {
            _ = startDecision(session: session, shuffleOn: settings.shuffleOn, songCount: 5, random: &rng)
            XCTAssertTrue(settings.shuffleOn); XCTAssertEqual(store.saves, 0)
        }
    }
}
