import XCTest
@testable import LocalPlayer
@testable import PlayawayCore

/// Story 40, TC-17: the Mac app, wired the way AppServices wires it but over a temp home, opens a playlist whose song
/// reference was made on the iPhone (a bookmark that resolves nowhere, the iPhone's path under iCloud Drive) and finds
/// the song in this Mac's iCloud Drive, plays it, and asks nothing. With the file gone it is missing, as before.
@MainActor
final class DriveRootPlaybackTests: XCTestCase {
    let home = TempDir("drivehome")
    var app: TestApp!
    static let iPhonePath = "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Mixdowns/track1.mp3"

    override func tearDown() async throws { app?.tearDown() }

    var driveRoot: URL { home.url.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true) }

    func makeApp() { app = TestApp(driveRoot: { CloudFolder.driveRootOnThisDevice(home: self.home.url) }) }

    func testAnIPhoneMadeReferenceToASongInICloudDrivePlaysOnTheMac() throws {
        let mixdowns = driveRoot.appendingPathComponent("Mixdowns")
        try FileManager.default.createDirectory(at: mixdowns, withIntermediateDirectories: true)
        let song = mixdowns.appendingPathComponent("track1.mp3")
        try FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: song)
        makeApp()
        let track = Track(id: UUID(), reference: TrackReference(bookmark: Data([0, 1]), lastKnownPath: Self.iPhonePath, fileName: "track1.mp3"))
        let doc = app.openSaved(Playlist(tracks: [track]), at: home.url.appendingPathComponent("Industrial.\(playlistFileExtension)"))
        var done = false; doc.resolveStatuses { done = true }; spin { done }
        XCTAssertEqual(doc.statuses.status(of: track.id), .resolved(song), "found at its portable location in this Mac's iCloud Drive")
        XCTAssertNil(app.services.resolver.accessNeeded(for: track.reference, besidePlaylistAt: home.url), "the Mac asks nothing")
        XCTAssertEqual(doc.playlist.tracks[0].reference, track.reference, "the iPhone's reference is kept as it is")
        let window = app.window(of: doc)
        window.reload()
        window.playRow(0)
        spin { self.app.services.engine.currentURL != nil }
        XCTAssertEqual(app.services.engine.currentURL?.canonicalPath, song.canonicalPath)
    }

    func testTheSameReferenceWithTheSongGoneFromICloudDriveIsMissing() throws {
        try FileManager.default.createDirectory(at: driveRoot.appendingPathComponent("Mixdowns"), withIntermediateDirectories: true)
        makeApp()
        let track = Track(id: UUID(), reference: TrackReference(bookmark: Data([0, 1]), lastKnownPath: Self.iPhonePath, fileName: "track1.mp3"))
        let doc = app.openSaved(Playlist(tracks: [track]), at: home.url.appendingPathComponent("Industrial.\(playlistFileExtension)"))
        var done = false; doc.resolveStatuses { done = true }; spin { done }
        XCTAssertEqual(doc.statuses.status(of: track.id), .missing)
        let window = app.window(of: doc)
        window.reload()
        window.playRow(0)
        spin(timeout: 1) { self.app.services.engine.currentURL != nil }
        XCTAssertNil(app.services.engine.currentURL, "a missing song does not start the engine")
    }
}
