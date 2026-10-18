import XCTest
@testable import PlayawayCore

/// Story 40, reference.cloud_roots: a reference made on another device found at its portable location on this one.
/// The temp home is laid out as a Mac lays it out; the references carry an iPhone's path and a bookmark that resolves
/// nowhere, exactly what the owner's playlists hold.
final class TrackResolverPortableTests: XCTestCase {
    let home = TempDir("home")
    var driveRoot: URL { home.url.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true) }
    var container: URL { home.url.appendingPathComponent("Library/Mobile Documents/iCloud~software~away~play/Documents", isDirectory: true) }
    static let iPhonePath = "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Mixdowns/Doo-bye/a.mp3"
    var foreign: TrackReference { TrackReference(bookmark: Data([0, 1, 2]), lastKnownPath: Self.iPhonePath, fileName: "a.mp3") }

    func roots() -> DirectCloudRoots {
        DirectCloudRoots(playawayDocuments: CloudFolder.documentsOnThisDevice(home: home.url), driveRoot: CloudFolder.driveRootOnThisDevice(home: home.url))
    }

    func layOut(_ file: String, under root: URL, data: Data = Data([1])) throws -> URL {
        let url = root.appendingPathComponent(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    func testASongFromTheIPhoneIsFoundInThisMacsICloudDrive() throws {          // TC-10
        let here = try layOut("Mixdowns/Doo-bye/a.mp3", under: driveRoot)
        let resolver = TrackResolver(roots: roots())
        let (status, ref) = resolver.resolve(foreign, besidePlaylistAt: nil)
        XCTAssertEqual(status, .resolved(here))
        XCTAssertEqual(ref, foreign, "the iPhone keeps its own reference; nothing is rewritten")
        XCTAssertNil(resolver.accessNeeded(for: foreign, besidePlaylistAt: nil))
    }

    func testAnOffloadedSongsPlaceholderCountsAsFound() throws {                  // TC-11
        _ = try layOut("Mixdowns/Doo-bye/.a.mp3.icloud", under: driveRoot, data: Data())
        let expected = driveRoot.appendingPathComponent("Mixdowns/Doo-bye/a.mp3")
        XCTAssertEqual(TrackResolver(roots: roots()).resolve(foreign, besidePlaylistAt: nil).0, .resolved(expected))
    }

    func testASongGoneFromICloudDriveIsMissing() throws {                        // TC-12
        try FileManager.default.createDirectory(at: driveRoot.appendingPathComponent("Mixdowns"), withIntermediateDirectories: true)
        let playlistFolder = home.url.appendingPathComponent("Playlists")
        try FileManager.default.createDirectory(at: playlistFolder, withIntermediateDirectories: true)
        let resolver = TrackResolver(roots: roots())
        XCTAssertEqual(resolver.resolve(foreign, besidePlaylistAt: playlistFolder).0, .missing)
        XCTAssertNil(resolver.accessNeeded(for: foreign, besidePlaylistAt: playlistFolder), "the Mac never asks: it could read the folder, the file is simply not there")
    }

    func testALiveBookmarkWinsAndTheRootsAreNeverConsulted() throws {             // TC-13
        let local = try layOut("Music/a.mp3", under: home.url)
        _ = try layOut("Mixdowns/Doo-bye/a.mp3", under: driveRoot)
        var ref = try XCTUnwrap(TrackReference.make(for: local))
        ref.cloudPath = .iCloudDrive("Mixdowns/Doo-bye/a.mp3")
        XCTAssertEqual(TrackResolver(roots: roots()).resolve(ref, besidePlaylistAt: nil).0, .resolved(local))
    }

    func testWithoutICloudDriveOnThisMacTheSongIsMissingAndNoPermissionIsAsked() {   // TC-14
        let resolver = TrackResolver(roots: DirectCloudRoots(playawayDocuments: nil, driveRoot: nil))
        XCTAssertEqual(resolver.resolve(foreign, besidePlaylistAt: nil).0, .missing)
        XCTAssertNil(resolver.accessNeeded(for: foreign, besidePlaylistAt: nil))
    }

    func testAPlayawayFolderReferenceStillResolvesThroughTheContainer() throws {   // TC-15
        let here = try layOut("Trip/a.mp3", under: container)
        let fromMac = TrackReference(bookmark: Data([9]), lastKnownPath: "/Users/someone/Library/Mobile Documents/iCloud~software~away~play/Documents/Trip/a.mp3", fileName: "a.mp3")
        XCTAssertEqual(TrackResolver(roots: roots()).resolve(fromMac, besidePlaylistAt: nil).0, .resolved(here))
        XCTAssertEqual(TrackResolver(cloudDocuments: container).resolve(fromMac, besidePlaylistAt: nil).0, .resolved(here), "the older form of the resolver keeps working")
    }

    func testAPathThatClimbsOutOfTheRootIsRefused() throws {                      // TC-16
        _ = try layOut("secret.mp3", under: home.url)
        let escaping = TrackReference(bookmark: Data(), lastKnownPath: "", fileName: "secret.mp3", cloudPath: .iCloudDrive("../../../secret.mp3"))
        XCTAssertNil(roots().url(for: .iCloudDrive("../../../secret.mp3")))
        XCTAssertEqual(TrackResolver(roots: roots()).resolve(escaping, besidePlaylistAt: nil).0, .missing)
        XCTAssertNil(roots().url(for: .iCloudDrive("")), "an empty remainder names the root, not a song")
    }
}
