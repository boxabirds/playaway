import XCTest
@testable import PlayawayCore

final class ICloudLocationTests: XCTestCase {
    private struct Vector: Decodable { let name: String; let root: String?; let url: String; let expected: String }

    func testEveryVectorGivesItsExpectedAnswer() throws {
        let location = try XCTUnwrap(Bundle.module.url(forResource: "ICloudLocationVectors", withExtension: "json", subdirectory: "Fixtures"))
        let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: location))
        XCTAssertGreaterThanOrEqual(vectors.count, 12)
        for vector in vectors {
            let root = vector.root.map { URL(fileURLWithPath: $0) }
            let url = vector.url.hasPrefix("/") ? URL(fileURLWithPath: vector.url) : URL(string: vector.url)!
            XCTAssertEqual(isStrictlyInside(url, folder: root), vector.expected == "insideContainer", vector.name)
        }
    }

    func testSymlinkedPrivatePathsCompareEqual() {
        let root = URL(fileURLWithPath: "/private/var/tmp-icloud-test/Playaway")
        XCTAssertTrue(isStrictlyInside(URL(fileURLWithPath: "/var/tmp-icloud-test/Playaway/song.mp3"), folder: root))
    }
}

final class FileAssessorTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/icloud/Playaway")
    /// Stands in for the system: files under /icloud are iCloud Drive files, wherever in iCloud Drive they are.
    private func assessor(existing: Set<String>, answer: @escaping (URL) -> Bool? = { $0.path.hasPrefix("/icloud/") }) -> FileAssessor {
        FileAssessor(isUbiquitous: answer, fileExists: { existing.contains($0.path) })
    }

    func testSongsAreSortedIntoInMissingAndNeedingATransfer() {
        let inside = URL(fileURLWithPath: "/icloud/Playaway/Road/a.mp3")
        let outside = URL(fileURLWithPath: "/Users/me/b.mp3")
        let gone = URL(fileURLWithPath: "/Users/me/gone.mp3")
        let result = assessor(existing: [inside.path, outside.path]).assess([inside, outside, gone, nil])
        XCTAssertEqual(result.classes, [.alreadyInICloud, .needsTransfer, .missingFile, .missingFile])
        XCTAssertTrue(result.needsPrompt)
    }

    func testNoPromptWhenEverySongIsAlreadyInICloud() {
        let inside = URL(fileURLWithPath: "/icloud/Playaway/Road/a.mp3")
        XCTAssertFalse(assessor(existing: [inside.path]).assess([inside]).needsPrompt)
    }

    func testNoPromptForAnEmptyPlaylistOrOnlyMissingFiles() {
        XCTAssertFalse(assessor(existing: []).assess([]).needsPrompt)
        XCTAssertFalse(assessor(existing: []).assess([URL(fileURLWithPath: "/x/a.mp3"), nil]).needsPrompt)
    }

    func testASongElsewhereInICloudDriveIsAlreadyInICloudAndIsNotAskedAbout() {
        // Owner decision 2026-10-15: an iCloud Drive file counts as in iCloud even outside the Playaway folder.
        let elsewhereInICloud = URL(fileURLWithPath: "/icloud/Music/song.mp3")
        let result = assessor(existing: [elsewhereInICloud.path]).assess([elsewhereInICloud])
        XCTAssertEqual(result.classes, [.alreadyInICloud])
        XCTAssertFalse(result.needsPrompt)
    }

    func testAnUndeterminableAnswerCountsAsNeedingATransfer() {
        let file = URL(fileURLWithPath: "/Users/me/b.mp3")
        XCTAssertEqual(assessor(existing: [file.path], answer: { _ in nil }).assess([file]).classes, [.needsTransfer])
    }
}

final class FilesPromptTests: XCTestCase {
    func testTheDialogWordingAndRolesAreTheOwners() {
        XCTAssertEqual(FilesPrompt.title, "Sync with iCloud: Files")
        XCTAssertEqual(FilesPrompt.message, "This is an iCloud playlist, and Some of the files in your playlist are not in iCloud.")
        XCTAssertEqual(FilesPrompt.buttons.map(\.label), ["Move to iCloud", "Copy to iCloud", "Add Without Syncing"])
        XCTAssertEqual(FilesPrompt.buttons.map(\.role), [.destructive, .defaultAction, .plain])
        XCTAssertEqual(FilesPrompt.buttons.map(\.choice), [.moveToICloud, .copyToICloud, .doNothing])
    }

    func testDismissingTheDialogIsAddWithoutSyncing() { XCTAssertEqual(FilesPrompt.dismissalChoice, .doNothing) }

    func testTheCopiedInsteadReportAppearsOnlyForOneOrMore() {
        XCTAssertNil(FilesPrompt.copiedInsteadReport(0))
        XCTAssertEqual(FilesPrompt.copiedInsteadReport(3), "3 files were on separate volumes or read only and copies were placed on iCloud, NOT moved")
    }

    func testFailuresAreNamedAndNilWhenThereAreNone() {
        XCTAssertNil(FilesPrompt.failureMessage([]))
        let failure = TransferFailure(id: UUID(), fileName: "a.mp3", reason: "disk full")
        XCTAssertTrue(FilesPrompt.failureMessage([failure])!.contains("a.mp3"))
    }
}

final class TransferDestinationTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/icloud/Playaway")

    func testAnOrdinaryNameGivesTheFolderUnderTheRoot() {
        XCTAssertEqual(transferDestination(root: root, playlistName: "Road Trip")?.path, "/icloud/Playaway/Road Trip")
    }

    func testUnsafeNamesStayASingleComponentInsideThePlaywayFolder() {
        for name in ["", "   ", "../../etc", "a/b", "a:b", ".hidden", "...", "x\\y", String(repeating: "z", count: 300)] {
            let destination = transferDestination(root: root, playlistName: name)!
            XCTAssertTrue(isStrictlyInside(destination.appendingPathComponent("song.mp3"), folder: root), "name: \(name)")
            XCTAssertEqual(destination.deletingLastPathComponent().path, root.path, "name: \(name)")
            XCTAssertLessThanOrEqual(destination.lastPathComponent.count, 100)
            XCTAssertFalse(destination.lastPathComponent.hasPrefix("."))
        }
    }

    func testAnUnavailableRootGivesNoDestination() { XCTAssertNil(transferDestination(root: nil, playlistName: "Road")) }
}

final class FileTransferRunnerTests: XCTestCase {
    private var dir: TempDir!
    private var root: URL!
    private let fs = SystemTransferFileSystem()

    override func setUp() {
        dir = TempDir("transfer")
        root = dir.url.appendingPathComponent("Playaway")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func makeSong(_ name: String, in folder: String = "elsewhere") throws -> TransferItem {
        let directory = dir.url.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data("audio \(name)".utf8).write(to: url)
        return TransferItem(id: UUID(), source: url)
    }

    func testMoveMovesFilesOnTheSameDiskAndKeepsContents() throws {
        let item = try makeSong("a.mp3")
        let destination = root.appendingPathComponent("Road")
        let result = runTransfer([item], choice: .move, destination: destination, fileSystem: fs)
        XCTAssertEqual(result.moved, 1); XCTAssertEqual(result.copiedInstead, 0); XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.source.path), "the original is gone after a move")
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("a.mp3")), Data("audio a.mp3".utf8))
        XCTAssertEqual(result.newLocations[item.id], destination.appendingPathComponent("a.mp3"))
    }

    func testCopyLeavesTheOriginalInPlace() throws {
        let item = try makeSong("a.mp3")
        let destination = root.appendingPathComponent("Road")
        let result = runTransfer([item], choice: .copy, destination: destination, fileSystem: fs)
        XCTAssertEqual(result.copied, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("a.mp3").path))
    }

    func testAReadOnlyOriginalIsCopiedInsteadOfMoved() throws {
        let item = try makeSong("a.mp3", in: "readonly")
        let parent = item.source.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path) }
        let result = runTransfer([item], choice: .move, destination: root.appendingPathComponent("Road"), fileSystem: fs)
        XCTAssertEqual(result.copiedInstead, 1); XCTAssertEqual(result.moved, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.source.path), "the original stays")
    }

    func testADifferentVolumeIsCopiedInsteadOfMoved() throws {
        struct OtherDisk: TransferFileSystem {
            let inner = SystemTransferFileSystem()
            func createDirectory(_ url: URL) throws { try inner.createDirectory(url) }
            func exists(_ url: URL) -> Bool { inner.exists(url) }
            func sameVolume(_ a: URL, _ b: URL) -> Bool { false }
            func canRemove(_ url: URL) -> Bool { true }
            func move(_ source: URL, to destination: URL) throws { try inner.move(source, to: destination) }
            func copy(_ source: URL, to destination: URL) throws { try inner.copy(source, to: destination) }
            func remove(_ url: URL) { inner.remove(url) }
        }
        let item = try makeSong("a.mp3")
        let result = runTransfer([item], choice: .move, destination: root.appendingPathComponent("Road"), fileSystem: OtherDisk())
        XCTAssertEqual(result.copiedInstead, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.source.path))
    }

    func testAFailingSongNeverStopsTheOthersOrTouchesItsOriginal() throws {
        struct FailsOnB: TransferFileSystem {
            let inner = SystemTransferFileSystem()
            func createDirectory(_ url: URL) throws { try inner.createDirectory(url) }
            func exists(_ url: URL) -> Bool { inner.exists(url) }
            func sameVolume(_ a: URL, _ b: URL) -> Bool { true }
            func canRemove(_ url: URL) -> Bool { true }
            func move(_ source: URL, to destination: URL) throws {
                if source.lastPathComponent == "b.mp3" { throw CocoaError(.fileWriteOutOfSpace) }
                try inner.move(source, to: destination)
            }
            func copy(_ source: URL, to destination: URL) throws { try inner.copy(source, to: destination) }
            func remove(_ url: URL) { inner.remove(url) }
        }
        let a = try makeSong("a.mp3"), b = try makeSong("b.mp3"), c = try makeSong("c.mp3")
        let destination = root.appendingPathComponent("Road")
        let result = runTransfer([a, b, c], choice: .move, destination: destination, fileSystem: FailsOnB())
        XCTAssertEqual(result.moved, 2)
        XCTAssertEqual(result.failures.map(\.fileName), ["b.mp3"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.source.path), "the failed song's original is untouched")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("b.mp3").path), "no partial file")
        XCTAssertNil(result.newLocations[b.id])
    }

    func testAFileAlreadyInTheFolderIsNeverOverwritten() throws {
        let item = try makeSong("a.mp3")
        let destination = root.appendingPathComponent("Road")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let existing = destination.appendingPathComponent("a.mp3")
        try Data("someone else".utf8).write(to: existing)
        let result = runTransfer([item], choice: .move, destination: destination, fileSystem: fs)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(try Data(contentsOf: existing), Data("someone else".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.source.path))
    }

    func testTheDestinationFolderIsCreatedWhenMissingAndReusedWhenPresent() throws {
        let destination = root.appendingPathComponent("Road")
        _ = runTransfer([try makeSong("a.mp3")], choice: .copy, destination: destination, fileSystem: fs)
        let second = runTransfer([try makeSong("b.mp3")], choice: .copy, destination: destination, fileSystem: fs)
        XCTAssertEqual(second.copied, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted(), ["a.mp3", "b.mp3"])
    }
}

final class SongIntakeFlowTests: XCTestCase {
    private final class RecordingPresenter: FilesPromptPresenting {
        var choice: FilesChoice
        var asked = 0
        var messages: [String] = []
        init(_ choice: FilesChoice) { self.choice = choice }
        func askFilesChoice() async -> FilesChoice { asked += 1; return choice }
        func show(message: String) async { messages.append(message) }
    }

    private var dir: TempDir!
    private var root: URL!

    override func setUp() {
        dir = TempDir("intake")
        root = dir.url.appendingPathComponent("Playaway")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private var fixturesKeptAlive: [PlaylistFixture] = []

    /// A playlist of real audio files in an "elsewhere" folder, plus one already inside the Playaway folder.
    private func makePlaylist(elsewhere: Int, inside: Int = 0) throws -> (Playlist, [URL]) {
        let source = PlaylistFixture(trackNames: Array(Fixtures.trackNames.prefix(elsewhere)))
        fixturesKeptAlive.append(source)       // its files are deleted when it goes, so it lives as long as the test
        var tracks = source.tracks
        var urls = source.urls
        if inside > 0 {
            let folder = root.appendingPathComponent("Road")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for index in 0..<inside {
                let url = folder.appendingPathComponent("inside\(index).mp3")
                let original = PlaylistFixture()
                fixturesKeptAlive.append(original)
                try FileManager.default.copyItem(at: original.urls[0], to: url)
                urls.append(url)
                tracks.append(Track(id: UUID(), reference: TrackReference.make(for: url)!))
            }
        }
        return (Playlist(tracks: tracks), urls)
    }

    private func flow(_ presenter: RecordingPresenter, urls: [URL]) -> SongIntakeFlow {
        let byTrack = Dictionary(uniqueKeysWithValues: zip((0..<urls.count).map { $0 }, urls))
        _ = byTrack
        return SongIntakeFlow(root: root, isUbiquitous: { [root] url in isStrictlyInside(url, folder: root) }, resolve: { track in
            if case .resolved(let url) = TrackResolver().resolve(track.reference).0 { return url } else { return nil }
        }, presenter: presenter)
    }

    func testNoQuestionWhenEverySongIsAlreadyInICloud() async throws {
        let (playlist, urls) = try makePlaylist(elsewhere: 0, inside: 2)
        let presenter = RecordingPresenter(.moveToICloud)
        let outcome = await flow(presenter, urls: urls).run(playlist: playlist, playlistName: "Road", tracks: playlist.tracks, source: .turnOnSync)
        XCTAssertEqual(presenter.asked, 0)
        XCTAssertFalse(outcome.asked)
        XCTAssertEqual(outcome.playlist, playlist)
    }

    func testAddWithoutSyncingMovesNothingAndLeavesThePlaylistAsItWas() async throws {
        let (playlist, urls) = try makePlaylist(elsewhere: 3)
        let before = try urls.map { try Data(contentsOf: $0) }
        let presenter = RecordingPresenter(.doNothing)
        let outcome = await flow(presenter, urls: urls).run(playlist: playlist, playlistName: "Road", tracks: playlist.tracks, source: .turnOnSync)
        XCTAssertEqual(presenter.asked, 1)
        XCTAssertEqual(outcome.choice, .doNothing)
        XCTAssertEqual(outcome.playlist, playlist)
        XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, before)
        XCTAssertTrue(presenter.messages.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Road").path), "no folder is created")
    }

    func testMoveRepointsEveryHandledSongKeepingOrderAndIdsAndSkipsSongsAlreadyInICloud() async throws {
        let (playlist, urls) = try makePlaylist(elsewhere: 3, inside: 1)
        let presenter = RecordingPresenter(.moveToICloud)
        let outcome = await flow(presenter, urls: urls).run(playlist: playlist, playlistName: "Road", tracks: playlist.tracks, source: .turnOnSync)
        XCTAssertEqual(outcome.result.moved, 3)
        XCTAssertEqual(outcome.playlist.tracks.map(\.id), playlist.tracks.map(\.id), "order and rows unchanged")
        XCTAssertEqual(outcome.playlist.tracks.last, playlist.tracks.last, "the song already inside is untouched")
        for track in outcome.playlist.tracks {
            guard case .resolved(let url) = TrackResolver().resolve(track.reference).0 else { return XCTFail("a row no longer resolves") }
            XCTAssertTrue(isStrictlyInside(url, folder: root))
        }
        XCTAssertTrue(urls.prefix(3).allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }, "originals are gone after a move")
    }

    func testCopyKeepsTheOriginalsAndPlaysTheCopies() async throws {
        let (playlist, urls) = try makePlaylist(elsewhere: 2)
        let outcome = await flow(RecordingPresenter(.copyToICloud), urls: urls).run(playlist: playlist, playlistName: "Road", tracks: playlist.tracks, source: .iPhoneAdd)
        XCTAssertEqual(outcome.result.copied, 2)
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        guard case .resolved(let url) = TrackResolver().resolve(outcome.playlist.tracks[0].reference).0 else { return XCTFail("did not resolve") }
        XCTAssertTrue(isStrictlyInside(url, folder: root))
    }

    func testEverySourceGivesTheSameOutcomeForTheSameSongsAndChoice() async throws {
        var outcomes: [Int] = []
        for source in [IntakeSource.turnOnSync, .drop, .script, .iPhoneAdd] {
            let (playlist, urls) = try makePlaylist(elsewhere: 2)
            let presenter = RecordingPresenter(.copyToICloud)
            let outcome = await flow(presenter, urls: urls).run(playlist: playlist, playlistName: "Road\(outcomes.count)", tracks: playlist.tracks, source: source)
            outcomes.append(outcome.result.copied * 100 + presenter.asked * 10 + presenter.messages.count)
        }
        XCTAssertEqual(Set(outcomes).count, 1, "no way of adding answers differently from another: \(outcomes)")
    }

    func testNothingHappensWhileICloudIsUnavailable() async throws {
        let (playlist, urls) = try makePlaylist(elsewhere: 2)
        let presenter = RecordingPresenter(.moveToICloud)
        let unavailable = SongIntakeFlow(root: nil, isUbiquitous: { _ in false }, resolve: { _ in urls[0] }, presenter: presenter)
        let outcome = await unavailable.run(playlist: playlist, playlistName: "Road", tracks: playlist.tracks, source: .turnOnSync)
        XCTAssertEqual(presenter.asked, 0)
        XCTAssertEqual(outcome.playlist, playlist)
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testSongsAlreadyElsewhereInICloudDriveAreNeitherAskedAboutNorMoved() async throws {
        let (playlist, urls) = try makePlaylist(elsewhere: 2)
        let presenter = RecordingPresenter(.moveToICloud)
        let allInICloudDrive = SongIntakeFlow(root: root, isUbiquitous: { _ in true }, resolve: { track in
            if case .resolved(let url) = TrackResolver().resolve(track.reference).0 { return url } else { return nil }
        }, presenter: presenter)
        let outcome = await allInICloudDrive.run(playlist: playlist, playlistName: "Road", tracks: playlist.tracks, source: .turnOnSync)
        XCTAssertEqual(presenter.asked, 0, "songs the person can already reach from their other devices are left alone")
        XCTAssertEqual(outcome.playlist, playlist)
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }
}
