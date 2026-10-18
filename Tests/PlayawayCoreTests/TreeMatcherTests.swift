import XCTest
@testable import PlayawayCore

/// Story 41, grant.match: finding songs again under a folder the person allowed.
final class TreeMatcherTests: XCTestCase {
    let id = UUID()
    func entry(_ path: String, size: Int64 = 100) -> TreeEntry { TreeEntry(relativePath: path, name: String(path.split(separator: "/").last!), size: size) }
    func probe(place: String? = nil, name: String = "a.mp3", size: Int64? = 100) -> SongProbe { SongProbe(id: id, savedPlace: place, fileName: name, fileSize: size) }
    func outcome(_ probe: SongProbe, _ entries: [TreeEntry]) -> MatchOutcome? { matchSongs([probe], in: entries)[id] }

    func testASongAtItsSavedPlaceIsMatchedThere() {                                 // TC-10
        XCTAssertEqual(outcome(probe(place: "Live/a.mp3"), [entry("Live/a.mp3"), entry("Other/a.mp3")]), .matched("Live/a.mp3"))
    }
    func testASongMovedToAnotherSubfolderIsFoundByNameAndSize() {                   // TC-11
        XCTAssertEqual(outcome(probe(place: "Old/a.mp3"), [entry("New/a.mp3")]), .matched("New/a.mp3"))
    }
    func testNameCaseDoesNotMatter() {                                              // TC-12
        XCTAssertEqual(outcome(probe(name: "A.MP3"), [entry("x/a.mp3")]), .matched("x/a.mp3"))
    }
    func testAnUnrecordedSizeMatchesByNameWhenExactlyOneFileHasIt() {               // TC-13
        XCTAssertEqual(outcome(probe(size: nil), [entry("x/a.mp3", size: 5)]), .matched("x/a.mp3"))
    }
    func testAnUnrecordedSizeWithTwoFilesOfThatNameIsNeverGuessed() {               // TC-14
        XCTAssertEqual(outcome(probe(size: nil), [entry("x/a.mp3"), entry("y/a.mp3")]), .ambiguous)
    }
    func testAFileOfTheSameNameAndAnotherSizeIsNotTheSong() {                       // TC-15
        XCTAssertEqual(outcome(probe(size: 100), [entry("x/a.mp3", size: 999)]), MatchOutcome.none)
    }
    func testTwoIdenticalCopiesAreAmbiguousUnlessTheSavedPlaceDecides() {           // TC-16
        let copies = [entry("x/a.mp3"), entry("y/a.mp3")]
        XCTAssertEqual(outcome(probe(place: nil), copies), .ambiguous)
        XCTAssertEqual(outcome(probe(place: "y/a.mp3"), copies), .matched("y/a.mp3"))
    }
    func testASongIcloudHasNotDownloadedIsMatchedByNameWhateverItsRecordedSize() {   // the owner's folders show download icons
        XCTAssertEqual(outcome(probe(size: 4_000_000), [TreeEntry(relativePath: "x/a.mp3", name: "a.mp3", size: TreeEntry.unknownSize)]), .matched("x/a.mp3"))
        XCTAssertEqual(TreeEntry.placeholderTarget(of: ".Aftershock s1.m4a.icloud"), "Aftershock s1.m4a")
        XCTAssertNil(TreeEntry.placeholderTarget(of: "Aftershock s1.m4a"))
        XCTAssertNil(TreeEntry.placeholderTarget(of: ".DS_Store"))
    }

    func testTheSystemListingNamesAPlaceholderByItsRealNameAndSkipsOtherHiddenFiles() throws {
        let dir = TempDir("placeholders")
        let sub = dir.url.appendingPathComponent("Live")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data(count: 5).write(to: sub.appendingPathComponent(".Evicted.mp3.icloud"))
        try Data(count: 7).write(to: sub.appendingPathComponent("Here.mp3"))
        try Data(count: 1).write(to: sub.appendingPathComponent(".DS_Store"))
        let entries = SystemFolderListing().entries(under: dir.url).sorted { $0.relativePath < $1.relativePath }
        XCTAssertEqual(entries, [TreeEntry(relativePath: "Live/Evicted.mp3", name: "Evicted.mp3", size: TreeEntry.unknownSize),
                                 TreeEntry(relativePath: "Live/Here.mp3", name: "Here.mp3", size: 7)])
    }

    func testAnEmptyTreeMatchesNothing() {                                          // TC-17
        XCTAssertEqual(outcome(probe(), []), MatchOutcome.none)
    }

    /// TC-18 (integration): 300 songs in a real 3000-file tree are matched from one listing.
    func testThreeHundredSongsInAThreeThousandFileTreeAreOneListing() throws {
        let dir = TempDir("tree")
        for folder in 0..<30 {
            let sub = dir.url.appendingPathComponent("F\(folder)")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            for file in 0..<100 { try Data([UInt8(file % 250)]).write(to: sub.appendingPathComponent("song-\(folder)-\(file).mp3")) }
        }
        final class Counting: FolderListing {
            var calls = 0
            func entries(under folder: URL, progress: (Int) -> Void, isCancelled: () -> Bool) -> [TreeEntry] {
                calls += 1; return SystemFolderListing().entries(under: folder, progress: progress, isCancelled: isCancelled)
            }
        }
        let listing = Counting()
        let tree = listing.entries(under: dir.url)
        XCTAssertEqual(tree.count, 3000)
        let probes = (0..<300).map { SongProbe(id: UUID(), savedPlace: nil, fileName: "song-\($0 / 10)-\($0 % 100).mp3", fileSize: 1) }
        let outcomes = matchSongs(probes, in: tree)
        XCTAssertEqual(outcomes.values.filter { if case .matched = $0 { return true } else { return false } }.count, 300)
        XCTAssertEqual(listing.calls, 1)
    }

    func testARememberedMatchResolvesInANewInstanceAndAVanishedFileAsksAgain() throws {   // TC-19, TC-20 (integration)
        let dir = TempDir("cache")
        let drive = dir.url.appendingPathComponent("Drive", isDirectory: true)
        let found = drive.appendingPathComponent("Mixdowns/New/a.mp3")
        try FileManager.default.createDirectory(at: found.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: found)
        let prefix = drive.canonicalPath + "/"
        let drivePath: (URL) -> String? = { url in url.canonicalPath.hasPrefix(prefix) ? String(url.canonicalPath.dropFirst(prefix.count)) : nil }
        let grants = InMemoryFolderGrantStore(), matches = InMemoryDeviceMatchStore()
        let roots = GrantedCloudRoots(playawayDocuments: nil, store: grants, matchStore: matches, drivePath: drivePath)
        roots.grant(pickedFolder: drive.appendingPathComponent("Mixdowns"))
        let saved = CloudPath.iCloudDrive("Mixdowns/Old/a.mp3")
        XCTAssertNil(roots.url(for: saved).flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }, "not at its saved place")
        roots.remember(["Mixdowns/Old/a.mp3": "Mixdowns/New/a.mp3"])
        let again = GrantedCloudRoots(playawayDocuments: nil, store: grants, matchStore: matches, drivePath: drivePath)
        XCTAssertEqual(again.url(for: saved)?.canonicalPath, found.canonicalPath, "a new instance over the same stores")
        XCTAssertNil(again.accessNeeded(for: saved))
        try FileManager.default.removeItem(at: found)
        XCTAssertNotEqual(again.url(for: saved)?.canonicalPath, found.canonicalPath, "the matched file vanished")
        XCTAssertTrue(matches.matches.moved.isEmpty, "and the entry was dropped")
    }
}
