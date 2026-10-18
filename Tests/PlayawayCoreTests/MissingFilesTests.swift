import XCTest
@testable import PlayawayCore

/// A real mounted disk image, the only reliable way to make a volume that can be unmounted.
final class DiskImage {
    let imageURL: URL
    let volumeName = "LPTest\(UUID().uuidString.prefix(6))"
    private(set) var mountPoint: URL?
    private let dir = TempDir("dmg")

    init() throws {
        imageURL = dir.path("test.dmg")
        try run("/usr/bin/hdiutil", ["create", "-size", "20m", "-fs", "APFS", "-volname", volumeName, imageURL.path])
        try attach()
    }

    func attach() throws {
        let output = try run("/usr/bin/hdiutil", ["attach", "-nobrowse", imageURL.path])
        guard let line = output.split(separator: "\n").last(where: { $0.contains("/Volumes/") }),
              let range = line.range(of: "/Volumes/") else { throw NSError(domain: "DiskImage", code: 1) }
        mountPoint = URL(fileURLWithPath: String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces))
    }

    func detach() throws {
        guard let mountPoint else { return }
        try run("/usr/bin/hdiutil", ["detach", "-force", mountPoint.path])
        self.mountPoint = nil
    }

    deinit { try? detach() }

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 { throw NSError(domain: "DiskImage", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output]) }
        return output
    }
}

@MainActor
final class TrackResolverTests: XCTestCase {
    let resolver = TrackResolver()

    func reference(for url: URL) -> TrackReference { TrackReference.make(for: url)! }

    func testUnchangedFileResolvesWithReferenceUnchanged() {            // C1
        let dir = TempDir()
        let url = dir.copyFixture("track1.mp3")
        let ref = reference(for: url)
        let (status, refreshed) = resolver.resolve(ref)
        XCTAssertEqual(status, .resolved(url))
        XCTAssertEqual(refreshed, ref, "TC-01: nothing to save")
    }

    func testMovedFileIsFollowedAndReferenceRefreshed() throws {                // C2 / prd.missing.track
        let dir = TempDir()
        let url = dir.copyFixture("track1.mp3")
        let ref = reference(for: url)
        let folder = dir.makeSubfolder("moved album")
        let newURL = folder.appendingPathComponent("track1.mp3")
        try FileManager.default.moveItem(at: url, to: newURL)
        let (status, refreshed) = resolver.resolve(ref)
        XCTAssertEqual(status, .resolved(newURL))
        XCTAssertEqual(refreshed.lastKnownPath, newURL.path)
        XCTAssertEqual(refreshed.fileName, "track1.mp3")
        XCTAssertNotEqual(refreshed, ref)
        let (again, same) = resolver.resolve(refreshed)
        XCTAssertEqual(again, .resolved(newURL))
        XCTAssertEqual(same, refreshed, "the second opening needs no further work")
    }

    func testRenamedFileInSameFolderIsFollowedByTheAlias() throws {
        let dir = TempDir()
        let url = dir.copyFixture("track1.mp3")
        let ref = reference(for: url)
        let renamed = dir.path("renamed.mp3")
        try FileManager.default.moveItem(at: url, to: renamed)
        XCTAssertEqual(resolver.resolve(ref).0, .resolved(renamed), "an alias follows renames too (more than required)")
    }

    func testDeletedFileIsMissing() throws {                                    // C4
        let dir = TempDir()
        let url = dir.copyFixture("track1.mp3")
        let ref = reference(for: url)
        try FileManager.default.removeItem(at: url)
        let (status, unchanged) = resolver.resolve(ref)
        XCTAssertEqual(status, .missing)
        XCTAssertEqual(unchanged, ref)
    }

    func testFileInTheTrashCountsAsDeleted() throws {
        let dir = TempDir()
        let url = dir.copyFixture("track1.mp3")
        let ref = reference(for: url)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        XCTAssertEqual(resolver.resolve(ref).0, .missing)
    }

    func testCorruptBookmarkFallsBackToLastKnownPath() {                 // TC-33
        let dir = TempDir()
        let url = dir.copyFixture("track1.mp3")
        var ref = reference(for: url)
        ref.bookmark = Data("garbage".utf8)
        let (status, rebuilt) = resolver.resolve(ref)
        XCTAssertEqual(status, .resolved(url))
        XCTAssertNotEqual(rebuilt.bookmark, ref.bookmark, "reference rebuilt")
        XCTAssertEqual(rebuilt.fileName, ref.fileName)
    }

    func testCorruptBookmarkAndGonePathIsMissingWithoutCrash() {         // TC-34
        let ref = TrackReference(bookmark: Data("garbage".utf8), lastKnownPath: "/nowhere/at/all.mp3", fileName: "all.mp3")
        XCTAssertEqual(resolver.resolve(ref).0, .missing)
        XCTAssertEqual(resolver.resolve(TrackReference(bookmark: Data(), lastKnownPath: "", fileName: "")).0, .missing)
    }

    func testFiftyTracksTwentyFiveMoved() throws {                              // TC-32
        let dir = TempDir()
        let target = dir.makeSubfolder("elsewhere")
        var refs: [TrackReference] = []
        for index in 0..<50 {
            let url = dir.copyFixture("track1.mp3", as: "t\(index).mp3")
            refs.append(reference(for: url))
            if index % 2 == 0 { try FileManager.default.moveItem(at: url, to: target.appendingPathComponent("t\(index).mp3")) }
        }
        let results = refs.map { resolver.resolve($0) }
        XCTAssertTrue(results.allSatisfy { if case .resolved = $0.0 { return true } else { return false } })
        XCTAssertEqual(zip(results, refs).filter { $0.0.1 != $0.1 }.count, 25)
    }

    func testVolumeDisconnectedIsMissingThenFoundAgain() throws {        // C5 / TC-09
        let image = try DiskImage()
        let url = image.mountPoint!.appendingPathComponent("track1.mp3")
        try FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: url)
        let ref = reference(for: url)
        XCTAssertEqual(resolver.resolve(ref).0, .resolved(url))
        try image.detach()
        XCTAssertEqual(resolver.resolve(ref).0, .missing, "disconnected drive: greyed out")
        try image.attach()
        guard case .resolved(let found) = resolver.resolve(ref).0 else { return XCTFail("reconnected drive: normal again") }
        XCTAssertEqual(found.lastPathComponent, "track1.mp3")
    }

    func testCopyThenDeleteToAnotherVolumeIsMissing() throws {           // C3
        let image = try DiskImage()
        let dir = TempDir()
        let url = dir.copyFixture("track1.mp3")
        let ref = reference(for: url)
        try FileManager.default.copyItem(at: url, to: image.mountPoint!.appendingPathComponent("track1.mp3"))
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(resolver.resolve(ref).0, .missing)
    }
}

@MainActor
final class PlaybackGateTests: XCTestCase {
    func testGateDecisions() {                                           // TC-38 / TC-37
        let url = Fixtures.url("track1.mp3")
        XCTAssertEqual(PlaybackGate().decide(for: .resolved(url)), .play(url))
        XCTAssertEqual(PlaybackGate().decide(for: .missing), .refuse)
    }
}

@MainActor
final class FolderMatcherTests: XCTestCase {
    let matcher = FolderMatcher()

    func testMatchesByNameCaseInsensitively() {                          // TC-46
        let dir = TempDir()
        dir.copyFixture("track1.mp3", as: "Track 01.MP3")
        let id = UUID()
        let matches = matcher.match(missing: [(id, "track 01.mp3")], in: dir.url)
        XCTAssertEqual(matches.map(\.id), [id])
        XCTAssertEqual(matches.first?.url.lastPathComponent, "Track 01.MP3")
    }

    func testEmptyUnreadableOrAbsentFolderYieldsNoMatches() {            // TC-47
        let dir = TempDir()
        XCTAssertTrue(matcher.match(missing: [(UUID(), "a.mp3")], in: dir.url).isEmpty)
        XCTAssertTrue(matcher.match(missing: [(UUID(), "a.mp3")], in: dir.path("nope")).isEmpty)
    }

    func testSubfoldersAreNotSearched() throws {                                // TC-48
        let dir = TempDir()
        let sub = dir.makeSubfolder("sub")
        try FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: sub.appendingPathComponent("a.mp3"))
        XCTAssertTrue(matcher.match(missing: [(UUID(), "a.mp3")], in: dir.url).isEmpty)
        XCTAssertTrue(matcher.match(missing: [(UUID(), "sub")], in: dir.url).isEmpty, "a folder is not a file match")
    }

    func testSearchNeverChangesAnyFile() throws {                               // TC-60
        let dir = TempDir()
        let files = (0..<5).map { dir.copyFixture("track\($0 + 1).mp3") }
        let before = files.map(FileSnapshot.init)
        let listing = try FileManager.default.contentsOfDirectory(atPath: dir.url.path).sorted()
        _ = matcher.match(missing: files.map { (UUID(), $0.lastPathComponent) }, in: dir.url)
        XCTAssertEqual(files.map(FileSnapshot.init), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.url.path).sorted(), listing)
    }

    func testFiftyMissingFiftyPresent() {                                // TC-50
        let dir = TempDir()
        let names = (0..<50).map { "t\($0).mp3" }
        for name in names { dir.copyFixture("track1.mp3", as: name) }
        XCTAssertEqual(matcher.match(missing: names.map { (UUID(), $0) }, in: dir.url).count, 50)
    }
}

/// A stand-in document that records what the relinker applies.
final class RecordingDocument: PlaylistDocumentEditing {
    var playlist: Playlist
    var applied: [(UUID, TrackReference)] = []
    var refuse = false
    init(_ playlist: Playlist) { self.playlist = playlist }
    func apply(_ updatedReference: TrackReference, toTrack id: UUID) {
        guard !refuse, let index = playlist.index(ofTrackWithID: id) else { return }
        playlist.tracks[index].reference = updatedReference
        applied.append((id, updatedReference))
    }
}

@MainActor
final class MissingTrackRelinkerTests: XCTestCase {
    /// Five tracks from one album folder; the listed ones are deleted so they are missing.
    @MainActor struct Rig {
        let fixture = PlaylistFixture()
        let statuses = TrackStatusStore()
        let marks = ReadabilityMarkStore()
        let document: RecordingDocument
        let relinker: MissingTrackRelinker
        let newFolder = TempDir("newhome")

        init(missing: [Int], matcher: FolderMatching = FolderMatcher()) {
            document = RecordingDocument(fixture.playlist)
            relinker = MissingTrackRelinker(statuses: statuses, marks: marks, matcher: matcher)
            for index in 0..<5 {
                if missing.contains(index) {
                    fixture.deleteFile(at: index)
                    statuses.set(.missing, for: fixture.tracks[index].id)
                    marks.markUnreadable(fixture.tracks[index])
                } else {
                    statuses.set(.resolved(fixture.urls[index]), for: fixture.tracks[index].id)
                }
            }
        }

        func putBack(_ indices: [Int], as names: [Int: String] = [:]) throws {
            for index in indices {
                try FileManager.default.copyItem(at: Fixtures.url(Fixtures.trackNames[index]),
                                                  to: newFolder.path(names[index] ?? Fixtures.trackNames[index]))
            }
        }

        func id(_ index: Int) -> UUID { fixture.tracks[index].id }
        func status(_ index: Int) -> TrackStatus? { statuses.status(of: id(index)) }
    }

    func testPickedSameNameWithMatchingMissingTracksInOneEdit() throws {       // TC-11 / acceptance 6
        let rig = Rig(missing: [1, 3, 4])
        try rig.putBack([1, 3])                                              // track 5 is not in the folder
        let result = rig.relinker.relink(trackID: rig.id(1), to: rig.newFolder.path("track2.mp3"), in: rig.document)
        XCTAssertEqual(result, .relinked([rig.id(1), rig.id(3)]))
        XCTAssertEqual(rig.status(1), .resolved(rig.newFolder.path("track2.mp3")))
        XCTAssertEqual(rig.status(3), .resolved(rig.newFolder.path("track4.mp3")))
        XCTAssertEqual(rig.status(4), .missing, "TC-65: a name not in the folder stays greyed out")
        XCTAssertEqual(rig.marks.mark(of: rig.fixture.tracks[1]), .readable, "hazard marks cleared")
        XCTAssertEqual(rig.marks.mark(of: rig.fixture.tracks[3]), .readable)
        XCTAssertEqual(rig.marks.mark(of: rig.fixture.tracks[4]), .unreadable)
        XCTAssertEqual(rig.document.applied.count, 2)
        XCTAssertEqual(TrackResolver().resolve(rig.document.playlist.tracks[3].reference).0, .resolved(rig.newFolder.path("track4.mp3")))
    }

    func testFolderWithNoMatchesRepairsOnlyTheLocatedTrack() throws {           // TC-12 / TC-15
        let rig = Rig(missing: [1, 3])
        try rig.putBack([1])
        XCTAssertEqual(rig.relinker.relink(trackID: rig.id(1), to: rig.newFolder.path("track2.mp3"), in: rig.document),
                       .relinked([rig.id(1)]))
        XCTAssertEqual(rig.status(3), .missing)
    }

    func testMatchesOnlyForTracksThatAreNotMissingAreIgnored() throws {         // TC-13 / TC-16
        let rig = Rig(missing: [1])
        try rig.putBack([1, 2])                                              // track 3 is present elsewhere and unchanged
        let originalReference = rig.document.playlist.tracks[2].reference
        XCTAssertEqual(rig.relinker.relink(trackID: rig.id(1), to: rig.newFolder.path("track2.mp3"), in: rig.document),
                       .relinked([rig.id(1)]))
        XCTAssertEqual(rig.document.playlist.tracks[2].reference, originalReference, "present tracks keep their references")
    }

    func testPickedFileWithDifferentNameStillUsed() throws {                    // TC-14
        let rig = Rig(missing: [1, 3])
        try rig.putBack([1, 3], as: [1: "other name.mp3"])
        let result = rig.relinker.relink(trackID: rig.id(1), to: rig.newFolder.path("other name.mp3"), in: rig.document)
        XCTAssertEqual(result, .relinked([rig.id(1), rig.id(3)]))
        XCTAssertEqual(rig.document.playlist.tracks[1].reference.fileName, "other name.mp3")
    }

    func testUnreadablePickIsRejectedAndNothingChanges() {               // TC-43
        let rig = Rig(missing: [1])
        let before = rig.document.playlist
        XCTAssertEqual(rig.relinker.relink(trackID: rig.id(1), to: rig.newFolder.url, in: rig.document), .notReadable)
        XCTAssertEqual(rig.relinker.relink(trackID: rig.id(1), to: rig.newFolder.path("nope.mp3"), in: rig.document), .notReadable)
        XCTAssertEqual(rig.document.playlist, before)
        XCTAssertEqual(rig.status(1), .missing)
        XCTAssertEqual(rig.marks.mark(of: rig.fixture.tracks[1]), .unreadable)
    }

    func testTrackNoLongerInDocumentIsEditRefused() throws {                    // TC-44
        let rig = Rig(missing: [1])
        try rig.putBack([1])
        let ghost = UUID()
        rig.statuses.set(.missing, for: ghost)
        XCTAssertEqual(rig.relinker.relink(trackID: ghost, to: rig.newFolder.path("track2.mp3"), in: rig.document), .editRefused)
        XCTAssertTrue(rig.document.applied.isEmpty)
        XCTAssertEqual(rig.marks.mark(of: rig.fixture.tracks[1]), .unreadable, "no mark cleared")
    }

    func testLocateIsRejectedOnATrackThatIsPresent() throws {                   // TC-42
        let rig = Rig(missing: [1])
        try rig.putBack([0])
        XCTAssertEqual(rig.relinker.relink(trackID: rig.id(0), to: rig.newFolder.path("track1.mp3"), in: rig.document), .editRefused)
        XCTAssertTrue(rig.document.applied.isEmpty)
    }

    func testMatchWhoseTrackLeftTheDocumentIsSkipped() throws {
        let rig = Rig(missing: [1, 3])
        try rig.putBack([1, 3])
        let gone = rig.id(3)
        let removing = Rig.RemovingMatcher(remove: gone, document: rig.document)
        let relinker = MissingTrackRelinker(statuses: rig.statuses, marks: rig.marks, matcher: removing)
        XCTAssertEqual(relinker.relink(trackID: rig.id(1), to: rig.newFolder.path("track2.mp3"), in: rig.document),
                       .relinked([rig.id(1)]))
    }

    func testLocateOnOnePlaylistDoesNotChangeAnother() throws {                 // TC-66
        let rig = Rig(missing: [1])
        try rig.putBack([1])
        let otherDocument = RecordingDocument(rig.fixture.playlist)
        _ = rig.relinker.relink(trackID: rig.id(1), to: rig.newFolder.path("track2.mp3"), in: rig.document)
        XCTAssertTrue(otherDocument.applied.isEmpty)
        XCTAssertEqual(otherDocument.playlist, rig.fixture.playlist)
    }

    func testRelinkNeverModifiesAudioFiles() throws {                           // TC-68
        let rig = Rig(missing: [1, 3])
        try rig.putBack([1, 3])
        let files = ["track2.mp3", "track4.mp3"].map { rig.newFolder.path($0) }
        let before = files.map(FileSnapshot.init)
        _ = rig.relinker.relink(trackID: rig.id(1), to: files[0], in: rig.document)
        XCTAssertEqual(files.map(FileSnapshot.init), before)
        XCTAssertEqual(rig.document.playlist.tracks.count, 5, "TC-61: nothing deleted from the playlist")
    }
}

extension MissingTrackRelinkerTests.Rig {
    struct RemovingMatcher: FolderMatching {
        let remove: UUID
        let document: RecordingDocument
        func match(missing: [(id: UUID, fileName: String)], in folder: URL) -> [(id: UUID, url: URL)] {
            nonisolated(unsafe) let document = document          // the relinker calls the matcher on the main actor
            let remove = remove
            MainActor.assumeIsolated { document.playlist.tracks.removeAll { $0.id == remove } }
            return FolderMatcher().match(missing: missing, in: folder)
        }
    }
}
