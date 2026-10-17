import XCTest
@testable import PlayawayCore

/// Story 39: two versions of one playlist, made on two devices, merge into one the same way on every device: every
/// song either had is kept, the newest version's order is the spine, a song only in an older version lands after its
/// nearest preceding neighbour that is in the spine, a reference inside the Playaway folder beats one outside.
final class PlaylistMergeTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/cloud/Documents")

    private func track(_ name: String, id: UUID = UUID(), inCloud: Bool = true) -> Track {
        let path = inCloud ? "/cloud/Documents/Dinner/\(name)" : "/Users/me/Music/\(name)"
        return Track(id: id, reference: TrackReference(bookmark: Data(), lastKnownPath: path, fileName: name))
    }

    private func version(_ tracks: [Track], at seconds: TimeInterval, bytes: Data? = nil) -> PlaylistVersion {
        let playlist = Playlist(tracks: tracks)
        return PlaylistVersion(playlist: playlist, modified: Date(timeIntervalSince1970: seconds), bytes: bytes ?? encoded(playlist))
    }

    private func encoded(_ playlist: Playlist) -> Data {
        let dir = TempDir("merge-encode")
        let url = dir.path("x.lplaylist")
        _ = PlaylistStore().save(playlist, to: url)
        return (try? Data(contentsOf: url)) ?? Data()
    }

    private func merge(_ versions: [PlaylistVersion]) -> Playlist {
        mergedPlaylist(versions) { CloudFolder.relativePath(inContainer: $0.lastKnownPath) != nil || $0.lastKnownPath.hasPrefix("/cloud/Documents/") }
    }

    private func names(_ playlist: Playlist) -> [String] { playlist.tracks.map(\.reference.fileName) }

    func testOneVersionComesBackAsItIs() {                                                       // TC-01
        let only = version([track("a.mp3"), track("b.mp3")], at: 10)
        XCTAssertEqual(merge([only]), only.playlist)
    }

    func testDisjointAddsAreUnitedOnTheNewestOrderWithTheOtherAddAfterItsNeighbour() {           // TC-02
        let a = track("a.mp3"), b = track("b.mp3"), c = track("c.mp3")
        let mac = version([a, b, track("mac.mp3")], at: 20)               // newest: the spine
        let phone = version([a, track("phone.mp3"), b, c], at: 10)        // older: phone.mp3 after a, c after b
        let merged = merge([phone, mac])
        XCTAssertEqual(names(merged), ["a.mp3", "phone.mp3", "b.mp3", "c.mp3", "mac.mp3"])
    }

    func testTheNewestOrderWinsOutright() {                                                       // TC-03
        let a = track("a.mp3"), b = track("b.mp3"), c = track("c.mp3")
        let older = version([a, b, c], at: 10)
        let newer = version([c, a, b], at: 20)
        XCTAssertEqual(names(merge([older, newer])), ["c.mp3", "a.mp3", "b.mp3"])
    }

    func testTheSameSongPrefersItsReferenceInsideThePlayawayFolderWhicheverIsNewer() {           // TC-04
        let id = UUID()
        let inside = track("a.mp3", id: id, inCloud: true), outside = track("a.mp3", id: id, inCloud: false)
        XCTAssertEqual(merge([version([outside], at: 20), version([inside], at: 10)]).tracks[0].reference, inside.reference)
        XCTAssertEqual(merge([version([inside], at: 20), version([outside], at: 10)]).tracks[0].reference, inside.reference)
    }

    func testTheSameDateIsBrokenByBytesSoEveryDeviceAgrees() {                                   // TC-05, TC-09
        let a = track("a.mp3"), b = track("b.mp3")
        let one = version([a, b], at: 10, bytes: Data("aaa".utf8))
        let two = version([b, a], at: 10, bytes: Data("bbb".utf8))
        XCTAssertEqual(merge([one, two]), merge([two, one]))
        XCTAssertEqual(names(merge([one, two])), ["b.mp3", "a.mp3"], "the greater bytes count as newer, so its order is the spine")
    }

    func testThreeVersionsAreAllUnitedWithOlderInsertsInDateOrder() {                             // TC-06
        let a = track("a.mp3"), b = track("b.mp3")
        let newest = version([a, b], at: 30)
        let middle = version([a, track("m.mp3"), b], at: 20)
        let oldest = version([a, b, track("o.mp3")], at: 10)
        XCTAssertEqual(names(merge([oldest, newest, middle])), ["a.mp3", "m.mp3", "b.mp3", "o.mp3"])
    }

    func testASongWithNoNeighbourInTheSpineGoesFirst() {                                          // TC-07
        let a = track("a.mp3")
        let newest = version([a], at: 20)
        let older = version([track("x.mp3"), track("y.mp3")], at: 10)
        XCTAssertEqual(names(merge([newest, older])), ["x.mp3", "y.mp3", "a.mp3"])
    }

    func testARemovalOnOneDeviceComesBackKnownLimitation() {                                      // TC-08
        let a = track("a.mp3"), b = track("b.mp3")
        let removedOnMac = version([a], at: 20)
        let phone = version([a, b], at: 10)
        XCTAssertEqual(names(merge([removedOnMac, phone])), ["a.mp3", "b.mp3"])
    }

    func testShuffledInputsGiveByteIdenticalOutput() {                                            // TC-09
        let a = track("a.mp3"), b = track("b.mp3"), c = track("c.mp3")
        let v1 = version([a, b], at: 30), v2 = version([b, c], at: 20), v3 = version([c, a], at: 10)
        let first = encoded(merge([v1, v2, v3])), second = encoded(merge([v3, v1, v2])), third = encoded(merge([v2, v3, v1]))
        XCTAssertEqual(first, second); XCTAssertEqual(second, third)
    }

    func testAnEmptyVersionAddsNothingAndRemovesNothing() {                                       // TC-10, TC-11
        let a = track("a.mp3"), b = track("b.mp3")
        XCTAssertEqual(names(merge([version([], at: 20), version([a, b], at: 10)])), ["a.mp3", "b.mp3"])
        XCTAssertEqual(merge([version([], at: 20)]).tracks, [])
        XCTAssertEqual(merge([]).tracks, [], "no versions: an empty playlist, not a crash")
    }

    func testTwoIdenticalVersionsGiveTheSamePlaylistSoACallerWritesNothing() {                    // TC-12
        let a = track("a.mp3"), b = track("b.mp3")
        let one = version([a, b], at: 20), two = version([a, b], at: 10)
        XCTAssertEqual(merge([one, two]), one.playlist)
    }
}
