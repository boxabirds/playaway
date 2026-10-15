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
        XCTAssertThrowsError(try library.create(named: "a/b")) { XCTAssertEqual($0 as? LibraryError, .invalidCharacters) }
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


final class PlaylistRenameTests: XCTestCase {
    private var dir: TempDir!
    private var library: PlaylistLibrary!
    private let store = PlaylistStore()

    override func setUp() {
        dir = TempDir("rename")
        library = PlaylistLibrary(folder: dir.url)
    }

    private func makePlaylist(_ name: String, songs: Int = 3) throws -> (URL, Playlist) {
        let fixture = PlaylistFixture()
        let playlist = Playlist(tracks: Array(fixture.tracks.prefix(songs)))
        let url = try library.create(named: name)
        XCTAssertEqual(library.save(playlist, to: url), .saved)
        return (url, playlist)
    }

    func testRenameMovesTheFileAndKeepsSongsAndOrder() throws {                       // TC-01
        let (url, playlist) = try makePlaylist("Morning")
        let new = try library.rename(url, to: "Evening")
        XCTAssertEqual(new.deletingLastPathComponent().path, url.deletingLastPathComponent().path)
        XCTAssertEqual(new.deletingPathExtension().lastPathComponent, "Evening")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "the old file is gone")
        guard case .loaded(let loaded) = library.load(new) else { return XCTFail("did not load") }
        XCTAssertEqual(loaded, playlist)
    }

    func testRenameToTheSameNameDoesNothing() throws {                                // TC-02
        let (url, _) = try makePlaylist("Morning")
        XCTAssertEqual(try library.rename(url, to: "Morning"), url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testCaseOnlyRenameIsNotAClash() throws {                                     // TC-03
        let (url, playlist) = try makePlaylist("morning")
        let new = try library.rename(url, to: "Morning")
        XCTAssertEqual(library.entries().map(\.name), ["Morning"])
        guard case .loaded(let loaded) = library.load(new) else { return XCTFail("did not load") }
        XCTAssertEqual(loaded, playlist)
    }

    func testClashWithAnotherPlaylistChangesNothing() throws {                        // TC-04
        let (a, playlistA) = try makePlaylist("A", songs: 2)
        let (b, playlistB) = try makePlaylist("B", songs: 3)
        XCTAssertThrowsError(try library.rename(a, to: "B")) { XCTAssertEqual($0 as? LibraryError, .alreadyExists) }
        guard case .loaded(let la) = library.load(a), case .loaded(let lb) = library.load(b) else { return XCTFail("did not load") }
        XCTAssertEqual(la, playlistA); XCTAssertEqual(lb, playlistB)
    }

    func testEmptyAndSpacesOnlyNamesAreRefused() throws {                             // TC-05, TC-06
        let (url, _) = try makePlaylist("A")
        for bad in ["", "   ", "\n\t"] {
            XCTAssertThrowsError(try library.rename(url, to: bad)) { XCTAssertEqual($0 as? LibraryError, .nameEmpty) }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSlashAndColonAreRefused() throws {                                       // TC-07, TC-08
        let (url, _) = try makePlaylist("A")
        for bad in ["a/b", "a:b"] {
            XCTAssertThrowsError(try library.rename(url, to: bad)) { XCTAssertEqual($0 as? LibraryError, .invalidCharacters) }
        }
        XCTAssertEqual(library.entries().map(\.name), ["A"])
    }

    func testRenamingAFileThatIsGoneFailsAndCreatesNothing() throws {                 // TC-09
        let (url, _) = try makePlaylist("A")
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try library.rename(url, to: "B")) {
            guard case .writeFailed? = $0 as? LibraryError else { return XCTFail("expected writeFailed, got \($0)") }
        }
        XCTAssertTrue(library.entries().isEmpty)
    }

    func testReadOnlyFolderFailsAndLeavesTheOldFile() throws {                        // TC-10
        let (url, _) = try makePlaylist("A")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.url.path) }
        XCTAssertThrowsError(try library.rename(url, to: "B")) {
            guard case .writeFailed? = $0 as? LibraryError else { return XCTFail("expected writeFailed, got \($0)") }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSurroundingSpacesAreTrimmed() throws {                                   // TC-11
        let (url, _) = try makePlaylist("A")
        XCTAssertEqual(try library.rename(url, to: "  Gym  ").deletingPathExtension().lastPathComponent, "Gym")
    }

    func testADamagedFileIsMovedAsIs() throws {                                       // TC-12
        let url = dir.url.appendingPathComponent("Broken.\(playlistFileExtension)")
        let bytes = Data("not a playlist".utf8)
        try bytes.write(to: url)
        let new = try library.rename(url, to: "Still broken")
        XCTAssertEqual(try Data(contentsOf: new), bytes, "contents are byte-identical: a rename never rewrites")
    }
}


final class PlaylistDeleteTests: XCTestCase {
    private var dir: TempDir!
    private var library: PlaylistLibrary!

    override func setUp() {
        dir = TempDir("delete")
        library = PlaylistLibrary(folder: dir.url)
    }

    func testDeleteRemovesOnlyThePlaylistFileAndLeavesSongsAndOtherPlaylists() throws {   // the story-33 negative cases
        let songs = PlaylistFixture(dir: dir)                      // song files in the same folder as the playlists
        let before = try songs.urls.map { try Data(contentsOf: $0) }
        let doomed = try library.create(named: "Doomed")
        let other = try library.create(named: "Other")
        XCTAssertEqual(library.save(songs.playlist, to: doomed), .saved)
        XCTAssertEqual(library.save(songs.playlist, to: other), .saved)
        let otherBytes = try Data(contentsOf: other)

        try library.delete(doomed)

        XCTAssertFalse(FileManager.default.fileExists(atPath: doomed.path))
        XCTAssertEqual(try songs.urls.map { try Data(contentsOf: $0) }, before, "song files untouched, byte for byte")
        XCTAssertEqual(try Data(contentsOf: other), otherBytes, "another playlist with the same songs is untouched")
        XCTAssertEqual(library.entries().map(\.name), ["Other"])
    }

    func testAnythingThatIsNotAPlaylistFileIsRefused() throws {
        let songs = PlaylistFixture(dir: dir)
        XCTAssertThrowsError(try library.delete(songs.urls[0])) { XCTAssertEqual($0 as? LibraryError, .notAPlaylist) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: songs.urls[0].path))
    }

    func testDeletingAFileThatIsGoneFails() throws {
        let url = try library.create(named: "A")
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try library.delete(url)) {
            guard case .writeFailed? = $0 as? LibraryError else { return XCTFail("expected writeFailed, got \($0)") }
        }
    }

    func testReadOnlyFolderFailsAndKeepsThePlaylist() throws {
        let url = try library.create(named: "A")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.url.path) }
        XCTAssertThrowsError(try library.delete(url)) {
            guard case .writeFailed? = $0 as? LibraryError else { return XCTFail("expected writeFailed, got \($0)") }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testADamagedPlaylistCanBeDeleted() throws {
        let url = dir.url.appendingPathComponent("Broken.\(playlistFileExtension)")
        try Data("nope".utf8).write(to: url)
        try library.delete(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

final class FolderPerPlaylistTests: XCTestCase {
    private var dir: TempDir!
    private var local: PlaylistLibrary!
    private var cloud: PlaylistLibrary!

    override func setUp() {
        dir = TempDir("folderlayout")
        let localFolder = dir.url.appendingPathComponent("phone")
        let cloudFolder = dir.url.appendingPathComponent("icloud")
        try? FileManager.default.createDirectory(at: localFolder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cloudFolder, withIntermediateDirectories: true)
        local = PlaylistLibrary(folder: localFolder)
        cloud = PlaylistLibrary(folder: cloudFolder, layout: .folderPerPlaylist)
    }

    func testCreateMakesAFolderNamedAfterThePlaylistWithTheFileInside() throws {
        let url = try cloud.create(named: "Road")
        XCTAssertEqual(url, cloud.folder.appendingPathComponent("Road/Road.\(playlistFileExtension)"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(cloud.entries().map(\.name), ["Road"])
        XCTAssertEqual(cloud.entries().first?.location, .iCloud)
        XCTAssertEqual(local.entries().first?.location, nil)
    }

    func testCreatingAPlaylistWhoseFolderExistsIsRefused() throws {
        try cloud.create(named: "Road")
        XCTAssertThrowsError(try cloud.create(named: "Road")) { XCTAssertEqual($0 as? LibraryError, .alreadyExists) }
    }

    func testPhonePlaylistsReportThePhoneAsTheirLocation() throws {
        try local.create(named: "Gym")
        XCTAssertEqual(local.entries().first?.location, .thisPhone)
    }

    func testRenamingRenamesTheFolderAndTheFileAndKeepsSongsInTheFolder() throws {
        let url = try cloud.create(named: "Road")
        let song = url.deletingLastPathComponent().appendingPathComponent("song.mp3")
        let songBytes = Data("pretend audio".utf8)
        try songBytes.write(to: song)
        let playlist = Playlist(tracks: Array(PlaylistFixture().tracks.prefix(2)))
        XCTAssertEqual(cloud.save(playlist, to: url), .saved)

        let renamed = try cloud.rename(url, to: "Trip")

        XCTAssertEqual(renamed, cloud.folder.appendingPathComponent("Trip/Trip.\(playlistFileExtension)"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.folder.appendingPathComponent("Road").path))
        XCTAssertEqual(try Data(contentsOf: cloud.folder.appendingPathComponent("Trip/song.mp3")), songBytes, "songs travel with the folder, untouched")
        guard case .loaded(let loaded) = cloud.load(renamed) else { return XCTFail("did not load") }
        XCTAssertEqual(loaded, playlist)
    }

    func testRenamingToAnExistingPlaylistIsRefusedAndChangesNothing() throws {
        let a = try cloud.create(named: "A")
        try cloud.create(named: "B")
        XCTAssertThrowsError(try cloud.rename(a, to: "B")) { XCTAssertEqual($0 as? LibraryError, .alreadyExists) }
        XCTAssertEqual(cloud.entries().map(\.name), ["A", "B"])
    }

    func testCaseOnlyRenameOfAFolderPlaylistWorks() throws {
        let url = try cloud.create(named: "road")
        let renamed = try cloud.rename(url, to: "Road")
        XCTAssertEqual(cloud.entries().map(\.name), ["Road"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testDeleteRemovesOnlyThePlaylistFileAndKeepsSongsAndTheirFolder() throws {
        let url = try cloud.create(named: "Road")
        let song = url.deletingLastPathComponent().appendingPathComponent("song.mp3")
        try Data("pretend audio".utf8).write(to: song)
        try cloud.delete(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: song.path), "a song kept in the folder is never deleted with the playlist")
        XCTAssertTrue(cloud.entries().isEmpty, "with no playlist file the folder is not listed as a playlist")
    }

    func testDeleteRemovesTheFolderWhenNothingElseIsInIt() throws {
        let url = try cloud.create(named: "Road")
        try cloud.delete(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }

    func testMoveIntoICloudMovesTheFileAndLeavesNothingBehind() throws {
        let source = try local.create(named: "Gym")
        let playlist = Playlist(tracks: Array(PlaylistFixture().tracks.prefix(3)))
        XCTAssertEqual(local.save(playlist, to: source), .saved)
        let moved = try cloud.adopt(source, using: PlainFileMover())
        XCTAssertEqual(moved, cloud.folder.appendingPathComponent("Gym/Gym.\(playlistFileExtension)"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path), "it is moved, not copied")
        guard case .loaded(let loaded) = cloud.load(moved) else { return XCTFail("did not load") }
        XCTAssertEqual(loaded, playlist)
        XCTAssertTrue(local.entries().isEmpty)
        XCTAssertEqual(cloud.entries().map(\.name), ["Gym"])
    }

    func testMoveIntoICloudRefusesATakenNameAndLeavesTheSourceUntouched() throws {
        try cloud.create(named: "Gym")
        let source = try local.create(named: "Gym")
        let bytes = try Data(contentsOf: source)
        XCTAssertThrowsError(try cloud.adopt(source, using: PlainFileMover())) { XCTAssertEqual($0 as? LibraryError, .alreadyExists) }
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    func testAFailedMoveLeavesTheSourceAndNoFolderBehind() throws {
        struct FailingMover: CloudMoving {
            func moveIntoCloud(_ source: URL, to destination: URL) throws { throw CocoaError(.fileWriteOutOfSpace) }
        }
        let source = try local.create(named: "Gym")
        XCTAssertThrowsError(try cloud.adopt(source, using: FailingMover())) {
            guard case .writeFailed? = $0 as? LibraryError else { return XCTFail("expected writeFailed, got \($0)") }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the source is still there")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloud.folder.appendingPathComponent("Gym").path), "no empty folder is left")
    }

    func testOnlyPlaylistFilesCanBeMoved() throws {
        let song = dir.url.appendingPathComponent("song.mp3")
        try Data("x".utf8).write(to: song)
        XCTAssertThrowsError(try cloud.adopt(song, using: PlainFileMover())) { XCTAssertEqual($0 as? LibraryError, .notAPlaylist) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: song.path))
    }
}
