import XCTest
@testable import PlayawayCore

/// An iCloud Drive file that has been offloaded from the device is not at its path any more; the system leaves a
/// placeholder named `.<name>.icloud` beside where it was. Such a song is not missing: it is in iCloud and can be
/// fetched, so the resolver must still find it (reported "in iCloud, not on this device" by the app, which then
/// downloads it on play). Reproduces "a song in iCloud that was offloaded shows as missing".
final class EvictedCloudFileTests: XCTestCase {
    private func evictedSong(in dir: TempDir, named name: String) throws -> URL {
        let real = dir.url.appendingPathComponent(name)
        let placeholder = dir.url.appendingPathComponent("." + name + ".icloud")
        try Data("placeholder".utf8).write(to: placeholder)
        return real
    }

    func testAnOffloadedSongResolvesToItsRealPathNotMissing() throws {
        let dir = TempDir("evicted")
        let real = try evictedSong(in: dir, named: "song.mp3")
        let reference = TrackReference(bookmark: Data(), lastKnownPath: real.path, fileName: "song.mp3")
        let (status, refreshed) = TrackResolver().resolve(reference)
        XCTAssertEqual(status, .resolved(real), "the placeholder stands for the song; it is in iCloud, not gone")
        XCTAssertEqual(refreshed.lastKnownPath, real.path)
        XCTAssertEqual(refreshed.fileName, "song.mp3")
    }

    func testAStaleBookmarkStillFindsTheOffloadedSongByItsPath() throws {
        let dir = TempDir("evicted")
        let real = dir.url.appendingPathComponent("song.mp3")
        try Data("audio".utf8).write(to: real)
        let made = try XCTUnwrap(TrackReference.make(for: real))
        try FileManager.default.removeItem(at: real)                 // iCloud takes the file away
        _ = try evictedSong(in: dir, named: "song.mp3")                  // and leaves the placeholder
        let (status, _) = TrackResolver().resolve(made)
        XCTAssertEqual(status, .resolved(real))
    }

    func testTheResolverStillReportsMissingWhenThereIsNoPlaceholderEither() {
        let dir = TempDir("evicted")
        let real = dir.url.appendingPathComponent("song.mp3")
        let reference = TrackReference(bookmark: Data(), lastKnownPath: real.path, fileName: "song.mp3")
        XCTAssertEqual(TrackResolver().resolve(reference).0, .missing)
    }

    func testTheOffloadedPlaceholderIsRecognised() throws {
        let dir = TempDir("evicted")
        let real = try evictedSong(in: dir, named: "song.mp3")
        XCTAssertTrue(iCloudPlaceholderExists(for: real))
        XCTAssertFalse(iCloudPlaceholderExists(for: dir.url.appendingPathComponent("other.mp3")))
    }
}
