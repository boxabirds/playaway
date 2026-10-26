import XCTest
@testable import PlayawayCore

/// Story 43, rename.size_match: a song renamed on another device, found on this one as the only file of its size in its folder.
/// Laid out as TrackResolverPortableTests lays it out: the reference carries a dead bookmark and the iPhone's path.
final class TrackResolverSizeMatchTests: XCTestCase {
    let home = TempDir("size")
    var driveRoot: URL { home.url.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true) }
    static let oldPath = "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Mixdowns/Doo-bye/a.mp3"
    static let size: Int64 = 5

    func reference(size: Int64? = size, path: String = oldPath) -> TrackReference {
        TrackReference(bookmark: Data([0, 1, 2]), lastKnownPath: path, fileName: "a.mp3", fileSize: size)
    }

    func resolver() -> TrackResolver {
        TrackResolver(roots: DirectCloudRoots(playawayDocuments: CloudFolder.documentsOnThisDevice(home: home.url),
                                              driveRoot: CloudFolder.driveRootOnThisDevice(home: home.url)))
    }

    @discardableResult
    func lay(_ name: String, bytes: Int = 5) throws -> URL {
        let url = driveRoot.appendingPathComponent("Mixdowns/Doo-bye/\(name)")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
        return url
    }

    func testTheOnlyFileOfThatSizeIsTheRenamedSong() throws {                       // TC-04
        let renamed = try lay("a (final).mp3")
        try lay("other.mp3", bytes: 9)
        let ref = reference()
        let (status, kept) = resolver().resolve(ref, besidePlaylistAt: nil)
        XCTAssertEqual(status, .resolved(renamed))
        XCTAssertEqual(kept, ref, "the shared playlist's reference is not rewritten")
    }

    func testTwoFilesOfThatSizeAreNotGuessedBetween() throws {                      // TC-05
        try lay("one.mp3"); try lay("two.mp3")
        XCTAssertEqual(resolver().resolve(reference(), besidePlaylistAt: nil).0, .missing)
    }

    func testNoFileOfThatSizeIsMissing() throws {                                    // TC-06
        try lay("other.mp3", bytes: 9)
        XCTAssertEqual(resolver().resolve(reference(), besidePlaylistAt: nil).0, .missing)
    }

    func testAnUnknownSizeIsNeverMatched() throws {                                  // TC-07
        try lay("a (final).mp3")
        XCTAssertEqual(resolver().resolve(reference(size: nil), besidePlaylistAt: nil).0, .missing)
    }

    func testAnEmptyFolderIsMissing() throws {                                       // TC-08
        try FileManager.default.createDirectory(at: driveRoot.appendingPathComponent("Mixdowns/Doo-bye"), withIntermediateDirectories: true)
        XCTAssertEqual(resolver().resolve(reference(), besidePlaylistAt: nil).0, .missing)
    }

    func testAFolderThatIsNotThereIsMissing() throws {                               // TC-09
        XCTAssertEqual(resolver().resolve(reference(), besidePlaylistAt: nil).0, .missing)
    }

    func testASongWithNoPortableLocationSearchesNothing() throws {                   // TC-10
        try lay("a (final).mp3")
        let ref = reference(path: "/Users/someone/Music/a.mp3")
        XCTAssertEqual(resolver().resolve(ref, besidePlaylistAt: nil).0, .missing)
    }
}
