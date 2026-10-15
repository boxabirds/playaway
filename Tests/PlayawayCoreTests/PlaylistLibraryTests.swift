import XCTest
@testable import PlayawayCore

final class PlaylistLibraryTests: XCTestCase {
    private var folder: URL!
    private var library: PlaylistLibrary!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        library = PlaylistLibrary(folder: folder)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func testEmptyFolderHasNoEntries() { XCTAssertTrue(library.entries().isEmpty) }

    func testCreateMakesAnEmptyPlaylistFileWithThatName() throws {
        let url = try library.create(named: "  Morning  ")
        XCTAssertEqual(url.lastPathComponent, "Morning.\(playlistFileExtension)")
        XCTAssertEqual(library.entries().map(\.name), ["Morning"])
        XCTAssertEqual(library.entries().first?.status, .ok(songCount: 0))
    }

    func testCreateRefusesEmptyNamesBadCharactersAndCollisions() throws {
        XCTAssertThrowsError(try library.create(named: "   ")) { XCTAssertEqual($0 as? LibraryError, .nameEmpty) }
        XCTAssertThrowsError(try library.create(named: "a/b")) { XCTAssertEqual($0 as? LibraryError, .nameEmpty) }
        let url = try library.create(named: "Run")
        let before = try Data(contentsOf: url)
        XCTAssertThrowsError(try library.create(named: "Run")) { XCTAssertEqual($0 as? LibraryError, .alreadyExists) }
        XCTAssertEqual(try Data(contentsOf: url), before, "an existing playlist is never replaced")
    }

    func testEntriesAreSortedIgnoringCaseAndCountSongs() throws {
        let b = try library.create(named: "banana"); _ = try library.create(named: "Apple")
        XCTAssertEqual(library.save(Playlist(tracks: bareTracks(3)), to: b), .saved)
        XCTAssertEqual(library.entries().map(\.name), ["Apple", "banana"])
        XCTAssertEqual(library.entries()[1].status, .ok(songCount: 3))
    }

    func testDamagedAndNewerVersionFilesAreListedAndNotRewritten() throws {
        let bad = folder.appendingPathComponent("Broken.\(playlistFileExtension)")
        let newer = folder.appendingPathComponent("Future.\(playlistFileExtension)")
        try Data("not json".utf8).write(to: bad)
        try Data(#"{"version": 99, "tracks": []}"#.utf8).write(to: newer)
        let entries = library.entries()
        XCTAssertEqual(entries.first { $0.name == "Broken" }?.status, .damaged)
        XCTAssertEqual(entries.first { $0.name == "Future" }?.status, .newerVersion(99))
        XCTAssertEqual(try Data(contentsOf: bad), Data("not json".utf8))
        XCTAssertEqual(try Data(contentsOf: newer), Data(#"{"version": 99, "tracks": []}"#.utf8))
    }

    func testOtherFilesAreIgnored() throws {
        try Data("x".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        XCTAssertTrue(library.entries().isEmpty)
    }
}

final class QuickEntriesTests: XCTestCase {
    func testQuickEntriesListNamesWithoutReadingFilesAndKeepTheOrderOfFullEntries() throws {
        let dir = TempDir("quick")
        let library = PlaylistLibrary(folder: dir.url)
        try library.create(named: "banana")
        try library.create(named: "Apple")
        try Data("not a playlist".utf8).write(to: dir.url.appendingPathComponent("Broken.\(playlistFileExtension)"))
        let quick = library.quickEntries()
        XCTAssertEqual(quick.map(\.name), library.entries().map(\.name), "the same order, so nothing moves when counts arrive")
        XCTAssertTrue(quick.allSatisfy { $0.status == .loading })
        XCTAssertEqual(quick.count, 3, "an unreadable file is listed; reading it later decides its status")
    }
}
