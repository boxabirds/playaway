import XCTest
@testable import PlayawayCore

/// Covers the advance matrix (TC-01..22 level 'unit' rows), skip forward/backward (TC-140..181) and the
/// boundary playlists, using a seeded shuffle so permutations are known exactly.
final class AdvanceDeciderTests: XCTestCase {
    let decider = AdvanceDecider()
    let tracks = bareTracks(5)
    var playlist: Playlist { Playlist(tracks: tracks) }
    let shuffler = seededShuffler()

    /// The seeded pass P1..P5 for the 5-track playlist.
    var pass: [Track] { shuffler.pass(for: playlist, startingWith: nil) }

    func context(current: Track?, repeatMode: RepeatMode, shuffle: Bool, pass: [Track]? = nil,
                 playlist: Playlist? = nil) -> AdvanceContext {
        AdvanceContext(playlist: playlist ?? self.playlist, current: current, repeatMode: repeatMode,
                       shuffleOn: shuffle, pass: pass ?? (shuffle ? self.pass : []), shuffler: shuffler)
    }

    func next(_ event: PlaybackEvent, _ current: Track?, _ mode: RepeatMode, shuffle: Bool,
              playlist: Playlist? = nil) -> Next {
        decider.advance(event: event, context: context(current: current, repeatMode: mode, shuffle: shuffle,
                                                       playlist: playlist)).next
    }

    // MARK: advance matrix

    func testAdvanceMatrix() {
        for shuffle in [false, true] {
            let order = shuffle ? pass : tracks
            for mode in RepeatMode.allCases {
                // E1: a track ends with a track remaining
                let mid = order[1]
                let e1 = next(.trackFinished, mid, mode, shuffle: shuffle)
                XCTAssertEqual(e1, mode == .one ? .play(mid) : .play(order[2]), "E1 \(mode) shuffle=\(shuffle)")

                // E2: the last track ends
                let last = order[4]
                let e2 = next(.trackFinished, last, mode, shuffle: shuffle)
                switch mode {
                case .off: XCTAssertEqual(e2, .stop, "E2 off shuffle=\(shuffle)")
                case .one: XCTAssertEqual(e2, .play(last), "E2 one shuffle=\(shuffle)")
                case .all:
                    if shuffle {
                        guard case .play = e2 else { return XCTFail("E2 all shuffle should play") }
                    } else {
                        XCTAssertEqual(e2, .play(tracks[0]))
                    }
                }

                // E3: the playlist is started
                let e3 = next(.start, nil, mode, shuffle: shuffle)
                XCTAssertEqual(e3, .play(shuffle ? pass[0] : tracks[0]), "E3 \(mode) shuffle=\(shuffle)")
            }
        }
    }

    func testRepeatAllWithShuffleStartsNewPass() {
        let result = decider.advance(event: .trackFinished,
                                     context: context(current: pass[4], repeatMode: .all, shuffle: true))
        XCTAssertNotNil(result.newPass, "TC-11: a new permutation pass starts")
        XCTAssertEqual(Set(result.newPass!.map(\.id)), Set(tracks.map(\.id)))
        XCTAssertEqual(result.next, .play(result.newPass![0]))
    }

    func testShuffleStartMayNotBeTrackOne() {
        // TC-06: first track of the seeded permutation, not necessarily track 1
        var firsts = Set<UUID>()
        for seed in UInt64(1)...20 {
            let order = seededShuffler(seed)
            let result = decider.advance(event: .start, context: AdvanceContext(
                playlist: playlist, current: nil, repeatMode: .off, shuffleOn: true, pass: [], shuffler: order))
            if case .play(let track) = result.next { firsts.insert(track.id) }
        }
        XCTAssertGreaterThan(firsts.count, 1, "different seeds must be able to start on different tracks")
    }

    // MARK: skip forward and backward

    func testSkipMatrix() {
        for shuffle in [false, true] {
            let order = shuffle ? pass : tracks
            for mode in RepeatMode.allCases {
                // skipForward
                XCTAssertEqual(next(.skipForward, order[0], mode, shuffle: shuffle), .play(order[1]), "fwd first \(mode) \(shuffle)")
                XCTAssertEqual(next(.skipForward, order[2], mode, shuffle: shuffle), .play(order[3]), "fwd mid \(mode) \(shuffle)")
                let fwdLast = next(.skipForward, order[4], mode, shuffle: shuffle)
                if mode == .off {
                    XCTAssertEqual(fwdLast, .stop, "fwd last off \(shuffle)")
                } else if shuffle {
                    let result = decider.advance(event: .skipForward, context: context(current: order[4], repeatMode: mode, shuffle: true))
                    XCTAssertNotNil(result.newPass, "TC-155/157: newly built pass")
                } else {
                    XCTAssertEqual(fwdLast, .play(order[0]), "fwd last \(mode)")
                }

                // skipBackward
                let backFirst = next(.skipBackward, order[0], mode, shuffle: shuffle)
                XCTAssertEqual(backFirst, mode == .off ? .stay : .play(order[4]), "back first \(mode) \(shuffle)")
                XCTAssertEqual(next(.skipBackward, order[2], mode, shuffle: shuffle), .play(order[1]), "back mid \(mode) \(shuffle)")
                XCTAssertEqual(next(.skipBackward, order[4], mode, shuffle: shuffle), .play(order[3]), "back last \(mode) \(shuffle)")
            }
        }
    }

    func testSkipBackwardWithShuffleDoesNotBuildNewPass() {
        let result = decider.advance(event: .skipBackward,
                                     context: context(current: pass[0], repeatMode: .all, shuffle: true))
        XCTAssertNil(result.newPass, "TC-93: no new pass is built")
        XCTAssertEqual(result.next, .play(pass[4]))
    }

    func testOneTrackPlaylist() {
        let single = Playlist(tracks: [tracks[0]])
        let only = tracks[0]
        for shuffle in [false, true] {
            XCTAssertEqual(next(.skipBackward, only, .off, shuffle: shuffle, playlist: single), .stay, "TC-176")
            XCTAssertEqual(next(.skipBackward, only, .all, shuffle: shuffle, playlist: single), .play(only), "TC-177")
            XCTAssertEqual(next(.skipForward, only, .off, shuffle: shuffle, playlist: single), .stop, "TC-178")
            XCTAssertEqual(next(.skipForward, only, .all, shuffle: shuffle, playlist: single), .play(only), "TC-179")
            // TC-76..78: finished track on a one-track playlist
            XCTAssertEqual(next(.trackFinished, only, .off, shuffle: shuffle, playlist: single), .stop)
            XCTAssertEqual(next(.trackFinished, only, .all, shuffle: shuffle, playlist: single), .play(only))
            XCTAssertEqual(next(.trackFinished, only, .one, shuffle: shuffle, playlist: single), .play(only))
        }
    }

    func testEmptyPlaylist() {
        let empty = Playlist()
        for shuffle in [false, true] {
            for mode in RepeatMode.allCases {
                XCTAssertEqual(next(.start, nil, mode, shuffle: shuffle, playlist: empty), .stop, "TC-80/86")
                XCTAssertEqual(next(.trackFinished, nil, mode, shuffle: shuffle, playlist: empty), .stop)
                XCTAssertEqual(next(.skipForward, nil, mode, shuffle: shuffle, playlist: empty), .stop, "TC-180")
                XCTAssertEqual(next(.skipBackward, nil, mode, shuffle: shuffle, playlist: empty), .stay, "TC-181")
            }
        }
    }

    func testRemovedCurrentTrackStops() {
        let removed = bareTracks(1)[0]
        XCTAssertEqual(next(.trackFinished, removed, .off, shuffle: false), .stop)
        XCTAssertEqual(next(.skipBackward, removed, .all, shuffle: false), .stay)
    }

    func testPassFollowsEditsMadeWhilePlaying() {
        let extra = bareTracks(1)[0]
        var edited = playlist
        edited.tracks.removeAll { $0.id == pass[2].id }
        edited.tracks.append(extra)
        let result = decider.advance(event: .trackFinished, context: AdvanceContext(
            playlist: edited, current: pass[1], repeatMode: .off, shuffleOn: true, pass: pass, shuffler: shuffler))
        XCTAssertEqual(result.next, .play(pass[3]), "removed track drops out of the pass")
    }

    func testRepeatCyclesOffAllOne() {
        XCTAssertEqual(RepeatMode.off.next, .all)
        XCTAssertEqual(RepeatMode.all.next, .one)
        XCTAssertEqual(RepeatMode.one.next, .off)
    }
}

final class ShuffleOrderTests: XCTestCase {
    func testPassIsPermutationWithEachTrackOnce() {
        let playlist = Playlist(tracks: bareTracks(8))
        let pass = seededShuffler().pass(for: playlist, startingWith: nil)
        XCTAssertEqual(pass.count, 8)
        XCTAssertEqual(Set(pass.map(\.id)), Set(playlist.tracks.map(\.id)))
    }

    func testRequestedTrackComesFirst() {
        let playlist = Playlist(tracks: bareTracks(5))
        for track in playlist.tracks {
            let pass = seededShuffler().pass(for: playlist, startingWith: track)
            XCTAssertEqual(pass.first, track)
            XCTAssertEqual(Set(pass.map(\.id)), Set(playlist.tracks.map(\.id)))
        }
    }

    func testSamePlaylistNotMutated() {
        let playlist = Playlist(tracks: bareTracks(5))
        let before = playlist
        _ = seededShuffler().pass(for: playlist, startingWith: nil)
        XCTAssertEqual(playlist, before, "TC-70: the stored order is unchanged")
    }

    func testEmptyPlaylistGivesEmptyPass() {
        XCTAssertTrue(seededShuffler().pass(for: Playlist(), startingWith: nil).isEmpty)
    }

    func testSeededGeneratorIsDeterministic() {
        var a = SeededGenerator(seed: 1), b = SeededGenerator(seed: 1)
        XCTAssertEqual((0..<5).map { _ in a.next() }, (0..<5).map { _ in b.next() })
    }
}
