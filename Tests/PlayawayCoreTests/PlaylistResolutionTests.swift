import XCTest
@testable import PlayawayCore

/// Audit item F4: one way to resolve a playlist's files for both apps. The Mac already resolved off the main thread and
/// applied the results afterwards (dropping any result made from a reference that changed meanwhile); the iPhone resolved
/// each row on the main thread as it was drawn. These cases pin the behaviour that moves into the core, so that moving it
/// cannot change what either app shows. Every outcome of a resolution is a case: found where the reference says, found
/// elsewhere, found as an offloaded placeholder, found through another device's reference, missing, a refreshed
/// reference, an empty playlist, order, and the stale-result rule.
final class PlaylistResolutionTests: XCTestCase {
    let dir = TempDir("resolution")

    func track(_ url: URL) -> Track { Track(id: UUID(), reference: TrackReference.make(for: url)!) }
    func song(_ name: String, in folder: String = "Songs") throws -> URL {
        let url = dir.url.appendingPathComponent(folder).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: url)
        return url
    }
    func resolve(_ tracks: [Track], beside: URL? = nil, roots: DirectCloudRoots = DirectCloudRoots(playawayDocuments: nil, driveRoot: nil)) -> [ResolvedTrack] {
        PlaylistResolution.resolve(tracks, with: TrackResolver(roots: roots), besidePlaylistAt: beside)
    }

    func testEverySongThatIsWhereItsReferenceSaysIsResolvedThere() throws {
        let a = try song("a.mp3"), b = try song("b.mp3")
        let tracks = [track(a), track(b)]
        let results = resolve(tracks)
        XCTAssertEqual(results.map(\.trackID), tracks.map(\.id), "in playlist order")
        XCTAssertEqual(results.map(\.status), [.resolved(a), .resolved(b)])
        XCTAssertEqual(results.map(\.refreshed), tracks.map(\.reference), "nothing needed refreshing")
    }

    func testASongThatCannotBeFoundIsMissing() throws {
        let gone = try song("gone.mp3")
        let t = track(gone)
        try FileManager.default.removeItem(at: gone)
        XCTAssertEqual(resolve([t]).map(\.status), [.missing])
    }

    func testAMovedSongIsResolvedAtItsNewPlaceWithARefreshedReference() throws {
        let a = try song("a.mp3")
        let t = track(a)
        let moved = dir.url.appendingPathComponent("Elsewhere/a.mp3")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: a, to: moved)
        let result = try XCTUnwrap(resolve([t]).first)
        XCTAssertEqual(result.status, .resolved(moved))
        XCTAssertNotEqual(result.refreshed, t.reference, "the stored place changed, so the reference was refreshed")
        XCTAssertEqual(result.refreshed.lastKnownPath, moved.canonicalPath)
        XCTAssertEqual(result.reference, t.reference, "the result remembers which reference it was made from")
    }

    func testASongAnotherDeviceSavedIsFoundBesideThePlaylistAndItsReferenceIsLeftAlone() throws {
        let playlistFolder = dir.url.appendingPathComponent("Playlist")
        let here = playlistFolder.appendingPathComponent("a.mp3")
        try FileManager.default.createDirectory(at: playlistFolder, withIntermediateDirectories: true)
        try Data([1]).write(to: here)
        let foreign = Track(id: UUID(), reference: TrackReference(bookmark: Data([9]), lastKnownPath: "/Users/someone/Music/a.mp3", fileName: "a.mp3"))
        let result = try XCTUnwrap(resolve([foreign], beside: playlistFolder).first)
        XCTAssertEqual(result.status.url?.canonicalPath, here.canonicalPath)
        XCTAssertEqual(result.refreshed, foreign.reference, "the author device keeps its own reference")
    }

    func testASongFoundThroughTheRootsIsResolvedAndItsReferenceIsLeftAlone() throws {
        let drive = dir.url.appendingPathComponent("Drive")
        let here = drive.appendingPathComponent("Mixdowns/a.mp3")
        try FileManager.default.createDirectory(at: here.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: here)
        let phone = Track(id: UUID(), reference: TrackReference(bookmark: Data([9]), lastKnownPath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Mixdowns/a.mp3", fileName: "a.mp3"))
        let result = try XCTUnwrap(resolve([phone], roots: DirectCloudRoots(playawayDocuments: nil, driveRoot: drive)).first)
        XCTAssertEqual(result.status.url?.canonicalPath, here.canonicalPath)
        XCTAssertEqual(result.refreshed, phone.reference)
    }

    func testAnOffloadedSongIsResolvedAtItsPlaceNotMissing() throws {
        let place = dir.url.appendingPathComponent("Songs/off.mp3")
        try FileManager.default.createDirectory(at: place.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: place.deletingLastPathComponent().appendingPathComponent(".off.mp3.icloud"))
        let t = Track(id: UUID(), reference: TrackReference(bookmark: Data(), lastKnownPath: place.path, fileName: "off.mp3"))
        XCTAssertEqual(resolve([t]).first?.status.url?.path, place.path)
    }

    func testAnEmptyPlaylistResolvesToNothing() {
        XCTAssertEqual(resolve([]), [])
    }

    func testTwoTracksThatNameTheSameFileAreResolvedIndependently() throws {
        let a = try song("a.mp3")
        let first = track(a), second = track(a)
        let results = resolve([first, second])
        XCTAssertEqual(results.map(\.trackID), [first.id, second.id])
        XCTAssertEqual(results.map(\.status), [.resolved(a), .resolved(a)])
    }

    /// The Mac's rule, kept: a result made from a reference that has since changed (a Locate raced the resolution) was
    /// resolved from a stale reference and is dropped rather than written over the newer state.
    func testAResultFromAReferenceThatChangedMeanwhileIsDropped() throws {
        let a = try song("a.mp3"), b = try song("b.mp3"), c = try song("c.mp3")
        let ta = track(a), tb = track(b), tc = track(c)
        let results = resolve([ta, tb, tc])
        var playlist = Playlist(tracks: [ta, tb, tc])
        playlist.tracks[1].reference = TrackReference(bookmark: Data([7]), lastKnownPath: "/located/elsewhere.mp3", fileName: "b.mp3")   // Locate
        playlist.tracks.removeAll { $0.id == tc.id }                                                                                    // removed
        let kept = PlaylistResolution.current(results, in: playlist)
        XCTAssertEqual(kept.map(\.trackID), [ta.id], "only the track whose reference is unchanged keeps its result")
    }

    func testEveryResultOfAnUnchangedPlaylistIsKept() throws {
        let tracks = [track(try song("a.mp3")), track(try song("b.mp3"))]
        let results = resolve(tracks)
        XCTAssertEqual(PlaylistResolution.current(results, in: Playlist(tracks: tracks)), results)
    }

    func testTheBackgroundFormRunsOffTheMainThreadAndHandsTheResultsBack() async throws {
        let a = try song("a.mp3")
        let t = track(a)
        var ranOnMain = true
        let results = await PlaylistResolution.resolveInBackground([t], with: TrackResolver(roots: DirectCloudRoots(playawayDocuments: nil, driveRoot: nil)),
                                                                     besidePlaylistAt: nil, observing: { ranOnMain = Thread.isMainThread })
        XCTAssertFalse(ranOnMain, "resolution never runs on the main thread")
        XCTAssertEqual(results.map(\.status), [.resolved(a)])
    }

    func testTheSnapshotAnswersFromTheResultsAndSaysNothingForASongItHasNotResolved() throws {
        let a = try song("a.mp3")
        let t = track(a), other = track(try song("b.mp3"))
        let snapshot = ResolutionSnapshot(resolve([t]))
        XCTAssertEqual(snapshot.url(for: t.id), a)
        XCTAssertEqual(snapshot.status(for: t.id), .resolved(a))
        XCTAssertNil(snapshot.status(for: other.id), "not resolved yet is not the same as missing")
        XCTAssertNil(snapshot.url(for: other.id))
        XCTAssertFalse(snapshot.isEmpty); XCTAssertTrue(ResolutionSnapshot([]).isEmpty)
    }
}

private extension TrackStatus {
    var url: URL? { if case .resolved(let url) = self { return url } else { return nil } }
}
