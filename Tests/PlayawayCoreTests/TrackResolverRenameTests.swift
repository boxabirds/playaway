import XCTest
@testable import PlayawayCore

/// A song renamed in Finder: what the Mac's resolver saves into the reference, which is what another device reads.
final class TrackResolverRenameTests: XCTestCase {
    let folder = TempDir("rename")

    func testARenamedSongIsFoundByItsBookmarkAndTheRepairedReferenceCarriesTheNewName() throws {
        let old = folder.url.appendingPathComponent("Doo-bye.mp3")
        try Data([1, 2, 3]).write(to: old)
        let reference = try XCTUnwrap(TrackReference.make(for: old))
        let renamed = folder.url.appendingPathComponent("Doo-bye (final).mp3")
        try FileManager.default.moveItem(at: old, to: renamed)

        let (status, repaired) = TrackResolver(cloudDocuments: nil).resolve(reference)

        guard case .resolved(let found) = status else { return XCTFail("the bookmark follows the rename; got \(status)") }
        XCTAssertEqual(found.canonicalPath, renamed.canonicalPath)
        XCTAssertEqual(repaired.lastKnownPath, renamed.canonicalPath, "the new place is what gets saved")
        XCTAssertEqual(repaired.fileName, "Doo-bye (final).mp3", "another device looks the song up by this name")
    }
}
