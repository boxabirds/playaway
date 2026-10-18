import XCTest
@testable import PlayawayCore

/// Story 40, grant.store: the folders a device has been allowed to read, kept as real bookmarks to a temp folder that
/// stands in for iCloud Drive. The bookmark behaviour under test is Foundation's own.
final class FolderGrantsTests: XCTestCase {
    let dir = TempDir("grants")
    var drive: URL { dir.url.appendingPathComponent("Drive", isDirectory: true) }
    var store = InMemoryFolderGrantStore()

    /// Roots over the stand-in drive: a picked folder's drive path is its path under the stand-in.
    func roots(playaway: URL? = nil) -> GrantedCloudRoots {
        let drivePath = drive.canonicalPath + "/"
        return GrantedCloudRoots(playawayDocuments: playaway, store: store, drivePath: { url in
            let path = url.canonicalPath
            return path.hasPrefix(drivePath) ? String(path.dropFirst(drivePath.count)) : nil
        })
    }

    func make(_ relative: String, file: Bool = true) throws -> URL {
        let url = drive.appendingPathComponent(relative)
        if file {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: url)
        } else {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    func testAPickedFolderBecomesAGrantInTheStore() throws {                       // TC-20
        let mixdowns = try make("Mixdowns", file: false)
        let roots = roots()
        XCTAssertEqual(store.grants, [])
        let grant = roots.grant(pickedFolder: mixdowns)
        XCTAssertEqual(grant?.drivePath, "Mixdowns")
        XCTAssertEqual(store.grants.map(\.drivePath), ["Mixdowns"])
        XCTAssertFalse(store.grants[0].bookmark.isEmpty)
    }

    func testAFolderOutsideICloudDriveIsRefusedAndNothingIsStored() throws {       // TC-21
        let elsewhere = dir.url.appendingPathComponent("Elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        XCTAssertNil(roots().grant(pickedFolder: elsewhere))
        XCTAssertNil(roots().grant(pickedFolder: drive), "the root itself cannot be granted")
        XCTAssertEqual(store.grants, [])
    }

    func testAGrantCoversTheFolderItsSubfoldersAndFilesAddedLater() throws {       // TC-22
        let mixdowns = try make("Mixdowns", file: false)
        let roots = roots()
        roots.grant(pickedFolder: mixdowns)
        let direct = try make("Mixdowns/a.mp3"), deep = try make("Mixdowns/Doo-bye/b.mp3")
        XCTAssertTrue(roots.covers(.iCloudDrive("Mixdowns/a.mp3")))
        XCTAssertEqual(roots.url(for: .iCloudDrive("Mixdowns/a.mp3"))?.canonicalPath, direct.canonicalPath)
        XCTAssertEqual(roots.url(for: .iCloudDrive("Mixdowns/Doo-bye/b.mp3"))?.canonicalPath, deep.canonicalPath)
        let later = try make("Mixdowns/New/c.mp3")
        XCTAssertEqual(roots.url(for: .iCloudDrive("Mixdowns/New/c.mp3"))?.canonicalPath, later.canonicalPath)
        XCTAssertNil(roots.accessNeeded(for: .iCloudDrive("Mixdowns/New/c.mp3")))
        // A fresh instance over the same store reopens the grant from its bookmark.
        let again = self.roots()
        XCTAssertEqual(again.url(for: .iCloudDrive("Mixdowns/a.mp3"))?.canonicalPath, direct.canonicalPath)
    }

    func testASiblingWithACommonPrefixIsNotCovered() throws {                      // TC-23
        let roots = roots()
        roots.grant(pickedFolder: try make("Mixdowns2", file: false))
        roots.grant(pickedFolder: try make("Mix", file: false))
        XCTAssertFalse(roots.covers(.iCloudDrive("Mixdowns2x/a.mp3")))
        XCTAssertFalse(roots.covers(.iCloudDrive("Mixdowns/a.mp3")))
        XCTAssertEqual(roots.accessNeeded(for: .iCloudDrive("Mixdowns/a.mp3")), "Mixdowns")
        XCTAssertNil(roots.url(for: .iCloudDrive("Mixdowns/a.mp3")))
    }

    func testAGrantWhoseFolderIsGoneIsDroppedAndAskedForAgain() throws {           // TC-24
        let mixdowns = try make("Mixdowns", file: false)
        let roots = roots()
        roots.grant(pickedFolder: mixdowns)
        XCTAssertEqual(store.grants.count, 1)
        try FileManager.default.removeItem(at: mixdowns)
        let fresh = self.roots()
        XCTAssertFalse(fresh.covers(.iCloudDrive("Mixdowns/a.mp3")))
        XCTAssertEqual(fresh.accessNeeded(for: .iCloudDrive("Mixdowns/a.mp3")), "Mixdowns")
        XCTAssertEqual(store.grants, [], "dropped from the store once it failed")
    }

    func testTheFolderToAskForIsTheOneMostSongsShare() {                            // TC-25, TC-26
        let paths: [CloudPath] = [.iCloudDrive("Mixdowns/a.mp3"), .iCloudDrive("Mixdowns/b/c.mp3"), .iCloudDrive("Mixdowns/d.mp3"),
                                  .iCloudDrive("Other/e.mp3"), .playawayFolder("Trip/f.mp3")]
        XCTAssertEqual(GrantedCloudRoots.folderToAsk(for: paths), "Mixdowns")
        XCTAssertNil(GrantedCloudRoots.folderToAsk(for: []))
        XCTAssertNil(GrantedCloudRoots.folderToAsk(for: [.playawayFolder("Trip/f.mp3"), .iCloudDrive("root.mp3")]))
        XCTAssertEqual(GrantedCloudRoots.folderToAsk(for: [.iCloudDrive("B/a.mp3"), .iCloudDrive("A/a.mp3")]), "A", "a tie goes to the first by name")
    }

    /// The phone that made the playlist: its own bookmarks open most songs, one was renamed since. It can read the
    /// folder, so nothing is asked; the renamed song is simply gone. Only a folder with no song found is asked for.
    func testAFolderWithASongFoundOnThisDeviceIsNeverAskedFor() {                   // TC-34
        let unfound: [CloudPath] = [.iCloudDrive("Mixdowns/Old Name.mp3"), .iCloudDrive("Mixdowns/b/Gone.mp3")]
        XCTAssertNil(GrantedCloudRoots.folderToAsk(for: unfound, found: [.iCloudDrive("Mixdowns/c.mp3")]))
        XCTAssertEqual(GrantedCloudRoots.folderToAsk(for: unfound, found: [.iCloudDrive("Other/x.mp3")]), "Mixdowns")
        XCTAssertEqual(GrantedCloudRoots.folderToAsk(for: unfound + [.iCloudDrive("Live/y.mp3")], found: [.iCloudDrive("Mixdowns/c.mp3")]), "Live")
        XCTAssertNil(GrantedCloudRoots.folderToAsk(for: unfound, found: [.iCloudDrive("Mixdowns/c.mp3"), .playawayFolder("Trip/z.mp3")]))
        XCTAssertEqual(GrantedCloudRoots.folderToAsk(for: unfound, found: [.playawayFolder("Trip/z.mp3")]), "Mixdowns", "a song in the Playaway folder says nothing about iCloud Drive")
    }

    func testTheFileStoreRoundTripsAndReadsGarbageAsNothing() throws {               // TC-27
        let file = dir.url.appendingPathComponent("Support/FolderGrants.json")
        let store = FolderGrantFileStore(url: file)
        XCTAssertEqual(store.load(), [])
        let grants = [FolderGrant(drivePath: "Mixdowns", bookmark: Data([1, 2, 3])), FolderGrant(drivePath: "Other/Deep", bookmark: Data([4]))]
        store.save(grants)
        XCTAssertEqual(FolderGrantFileStore(url: file).load(), grants)
        try Data("not json".utf8).write(to: file)
        XCTAssertEqual(FolderGrantFileStore(url: file).load(), [])
    }

    func testAPlayawayFolderPathGoesUnderTheContainerWhenThereIsOne() throws {       // TC-28
        let documents = dir.url.appendingPathComponent("Container/Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let with = roots(playaway: documents)
        XCTAssertEqual(with.url(for: .playawayFolder("Trip/a.mp3")), documents.appendingPathComponent("Trip/a.mp3"))
        XCTAssertNil(with.accessNeeded(for: .playawayFolder("Trip/a.mp3")))
        let without = roots(playaway: nil)
        XCTAssertNil(without.url(for: .playawayFolder("Trip/a.mp3")))
        XCTAssertNil(without.accessNeeded(for: .playawayFolder("Trip/a.mp3")), "the container needs no permission, only iCloud")
    }
}
