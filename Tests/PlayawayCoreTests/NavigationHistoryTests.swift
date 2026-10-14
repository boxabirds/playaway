import XCTest
@testable import PlayawayCore

final class NavigationHistoryTests: XCTestCase {
    typealias History = NavigationHistory<String>

    func testNewHistoryIsAtThePlaylistsScreenWithNothingToGoBackTo() {           // TC-60, TC-67
        var history = History()
        XCTAssertEqual(history.current, .playlists)
        XCTAssertFalse(history.canGoBack)
        XCTAssertNil(history.previous)
        XCTAssertNil(history.back())
        XCTAssertEqual(history.current, .playlists)
    }

    func testNavigatingRecordsWhereThePersonWas() {                              // TC-61
        var history = History()
        history.navigate(to: .playlist("Dinner"))
        XCTAssertEqual(history.current, .playlist("Dinner"))
        XCTAssertEqual(history.previous, .playlists)
    }

    func testNavigatingToTheShownDestinationRecordsNothing() {                   // TC-62
        var history = History()
        history.navigate(to: .playlists)
        XCTAssertFalse(history.canGoBack)
        history.navigate(to: .playlist("Dinner"))
        let before = history
        history.navigate(to: .playlist("Dinner"))
        XCTAssertEqual(history, before)
    }

    func testBackReturnsDestinationsInReverseOrderThenNothing() {                // TC-63
        var history = History()
        for name in ["A", "B", "C"] { history.navigate(to: .playlist(name)) }
        XCTAssertEqual(history.back(), .playlist("B"))
        XCTAssertEqual(history.back(), .playlist("A"))
        XCTAssertEqual(history.back(), .playlists)
        XCTAssertNil(history.back())
        XCTAssertEqual(history.current, .playlists)
    }

    func testFollowingALinkFromAPlaylistComesBackToThatPlaylist() {              // TC-64
        var history = History()
        history.navigate(to: .playlist("Dinner"))
        history.navigate(to: .playlist("Morning"))
        XCTAssertEqual(history.previous, .playlist("Dinner"), "not the Playlists screen")
    }

    func testARevisitedDestinationIsRecordedAgain() {                            // TC-66
        var history = History()
        history.navigate(to: .playlist("A"))
        history.navigate(to: .playlist("B"))
        history.navigate(to: .playlist("A"))
        XCTAssertEqual(history.playlistTrail, ["A", "B", "A"])
        XCTAssertEqual(history.back(), .playlist("B"))
    }

    func testAChainOfFourBacksOutCompletely() {
        var history = History()
        for name in ["A", "B", "C", "D"] { history.navigate(to: .playlist(name)) }
        var visited: [NavigationDestination<String>] = []
        while let destination = history.back() { visited.append(destination) }
        XCTAssertEqual(visited, [.playlist("C"), .playlist("B"), .playlist("A"), .playlists])
    }

    func testTrailMatchesTheStackAndRoundTrips() {
        let history = History(playlists: ["A", "B", "C"])
        XCTAssertEqual(history.current, .playlist("C"))
        XCTAssertEqual(history.previous, .playlist("B"))
        XCTAssertEqual(history.playlistTrail, ["A", "B", "C"])
        XCTAssertEqual(History(playlists: []), History())
    }

    func testNoDepthLimitIsAssumed() {
        var history = History()
        for index in 0..<1_000 { history.navigate(to: .playlist("P\(index)")) }
        XCTAssertEqual(history.playlistTrail.count, 1_000)
    }
}

final class UnsavedPlaylistTests: XCTestCase {
    private struct FakeSheet: SaveSheet {
        enum Behaviour { case destination(URL), cancel, fail }
        var behaviour: Behaviour
        func save(fileAt temporary: URL, suggestedName: String) async throws -> URL? {
            switch behaviour {
            case .cancel: return nil
            case .fail: throw CocoaError(.fileWriteNoPermission)
            case .destination(let folder):
                let target = folder.appendingPathComponent(temporary.lastPathComponent)
                try FileManager.default.copyItem(at: temporary, to: target)
                return target
            }
        }
    }

    func testLinkActionForEachAvailability() {                                    // TC-69, TC-75, TC-79
        XCTAssertEqual(linkAction(for: .available), .navigate)
        XCTAssertEqual(linkAction(for: .deleted), .offerSave)
        XCTAssertEqual(linkAction(for: .moved), .offerSave)
        XCTAssertEqual(linkAction(for: .notDelivered), .offerSave)
        XCTAssertEqual(linkAction(for: .none), .noLink)
    }

    func testSavedFileHoldsTheSameSongsInTheSameOrder() async throws {            // TC-71
        for count in [1, 40] {
            let fixture = PlaylistFixture()
            let playlist = Playlist(tracks: (0..<count).map { Track(id: UUID(), reference: fixture.tracks[$0 % fixture.tracks.count].reference) })
            let destination = TempDir("unsaved-dest")
            let result = await saveUnsavedPlaylist(playlist, suggestedName: "Rescued",
                                                   using: FakeSheet(behaviour: .destination(destination.url)))
            guard case .saved(let url) = result else { return XCTFail("expected saved, got \(result)") }
            XCTAssertEqual(url.pathExtension, playlistFileExtension)
            guard case .loaded(let loaded) = PlaylistStore().load(from: url) else { return XCTFail("file did not decode") }
            XCTAssertEqual(loaded.tracks.map(\.id), playlist.tracks.map(\.id))
        }
    }

    func testCancellingWritesNothing() async throws {                             // TC-72
        let fixture = PlaylistFixture()
        let destination = TempDir("unsaved-dest")
        let result = await saveUnsavedPlaylist(fixture.playlist, suggestedName: "Rescued", using: FakeSheet(behaviour: .cancel))
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.url.path), [])
    }

    func testAFailedWriteIsReportedAndAnotherAttemptWorks() async throws {        // TC-73
        let fixture = PlaylistFixture()
        let result = await saveUnsavedPlaylist(fixture.playlist, suggestedName: "Rescued", using: FakeSheet(behaviour: .fail))
        guard case .failed = result else { return XCTFail("expected failed, got \(result)") }
        let destination = TempDir("unsaved-dest")
        let second = await saveUnsavedPlaylist(fixture.playlist, suggestedName: "Rescued",
                                               using: FakeSheet(behaviour: .destination(destination.url)))
        guard case .saved = second else { return XCTFail("second attempt should save, got \(second)") }
    }

    func testNoTemporaryFileIsLeftBehind() async throws {
        let before = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("unsaved-") }.count
        _ = await saveUnsavedPlaylist(PlaylistFixture().playlist, suggestedName: "Rescued", using: FakeSheet(behaviour: .cancel))
        let after = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("unsaved-") }.count
        XCTAssertEqual(after, before)
    }
}
