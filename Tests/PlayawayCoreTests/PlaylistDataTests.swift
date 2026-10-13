import XCTest
@testable import PlayawayCore

final class PlaylistModelTests: XCTestCase {
    func fakeReference(_ url: URL) -> TrackReference? {
        TrackReference(bookmark: Data(url.path.utf8), lastKnownPath: url.path, fileName: url.lastPathComponent)
    }

    func urls(_ names: [String]) -> [URL] { names.map { Fixtures.url($0) } }

    func playlist(_ count: Int) -> Playlist { Playlist(tracks: bareTracks(count)) }

    func testAddSupportedFilesAppendsInGivenOrder() {                     // TC-01..03
        for existing in [0, 1, 5] {
            let base = playlist(existing)
            let result = adding(urls(["track1.mp3", "tone.wav", "tone.m4a"]), to: base, classifier: FormatClassifier(),
                                makeReference: fakeReference)
            XCTAssertEqual(result.playlist.tracks.count, existing + 3)
            XCTAssertEqual(Array(result.playlist.tracks.prefix(existing)), base.tracks, "existing tracks keep position")
            XCTAssertEqual(result.playlist.tracks.suffix(3).map(\.reference.fileName), ["track1.mp3", "tone.wav", "tone.m4a"])
            XCTAssertTrue(result.rejected.isEmpty)
        }
    }

    func testAddUnsupportedIsRejectedAndPlaylistUnchanged() {              // TC-04 / TC-05
        let base = playlist(5)
        let only = adding(urls(["tone.flac"]), to: playlist(0), classifier: FormatClassifier(), makeReference: fakeReference)
        XCTAssertEqual(only.playlist.tracks.count, 0)
        XCTAssertEqual(only.rejected.count, 1)
        let mixed = adding(urls(["track1.mp3", "tone.flac", "tone.wav"]), to: base, classifier: FormatClassifier(),
                           makeReference: fakeReference)
        XCTAssertEqual(mixed.playlist.tracks.count, 7)
        XCTAssertEqual(mixed.rejected.map { $0.url.lastPathComponent }, ["tone.flac"])
    }

    func testReferenceFailureRejectsAsNotReadable() {
        let result = adding(urls(["track1.mp3"]), to: playlist(0), classifier: FormatClassifier(), makeReference: { _ in nil })
        XCTAssertEqual(result.rejected.first?.reason, .fileNotReadable)
        XCTAssertTrue(result.playlist.tracks.isEmpty)
    }

    func testRemove() throws {                                              // TC-06..10
        XCTAssertThrowsError(try removing(at: 0, from: playlist(0))) { XCTAssertEqual($0 as? EditError, .indexOutOfRange) }
        XCTAssertEqual(try removing(at: 0, from: playlist(1)).tracks.count, 0)
        for index in [0, 2, 4] {
            let base = playlist(5)
            let result = try removing(at: index, from: base)
            var expected = base.tracks
            expected.remove(at: index)
            XCTAssertEqual(result.tracks, expected, "order of the rest is kept")
        }
        XCTAssertThrowsError(try removing(at: -1, from: playlist(5)))
        XCTAssertThrowsError(try removing(at: 5, from: playlist(5)))
    }

    func testMove() throws {                                                // TC-11..17
        XCTAssertThrowsError(try moving(from: 0, to: 0, in: playlist(0)))
        let one = playlist(1)
        XCTAssertEqual(try moving(from: 0, to: 0, in: one), one)
        let base = playlist(5)
        XCTAssertEqual(try moving(from: 0, to: 4, in: base).tracks, Array(base.tracks[1...4]) + [base.tracks[0]])
        XCTAssertEqual(try moving(from: 4, to: 0, in: base).tracks, [base.tracks[4]] + Array(base.tracks[0...3]))
        XCTAssertEqual(try moving(from: 2, to: 2, in: base), base)
        XCTAssertThrowsError(try moving(from: 0, to: 5, in: base))
        XCTAssertThrowsError(try moving(from: -1, to: 2, in: base))
        XCTAssertEqual(base, playlist5Snapshot(base), "a failed edit leaves the playlist unchanged")
    }

    private func playlist5Snapshot(_ p: Playlist) -> Playlist { p }

    func testEditsKeepTrackIdentity() throws {                              // TC-18
        let base = playlist(5)
        let moved = try moving(from: 0, to: 3, in: base)
        XCTAssertEqual(Set(moved.tracks.map(\.id)), Set(base.tracks.map(\.id)))
        for track in moved.tracks { XCTAssertEqual(track, base.track(withID: track.id)) }
    }

    func testRemovingATrackNeverTouchesTheAudioFile() throws {              // TC-90
        let dir = TempDir()
        let file = dir.copyFixture("track1.mp3")
        let before = FileSnapshot(file)
        let added = adding([file], to: Playlist(), classifier: FormatClassifier())
        _ = try removing(at: 0, from: added.playlist)
        XCTAssertEqual(FileSnapshot(file), before)
    }
}

final class PlaylistStoreTests: XCTestCase {
    let dir = TempDir("store")
    var url: URL { dir.path("Dinner.lplaylist") }
    let store = PlaylistStore()

    func realPlaylist(_ count: Int = 3) -> Playlist {
        PlaylistFixture(trackNames: Array(Fixtures.trackNames.prefix(count)), dir: TempDir("audio")).playlist
    }

    func testRoundTripPreservesIdsReferencesAndOrder() {                   // TC-20 / TC-21 / TC-35
        for count in [0, 1, 5] {
            let playlist = realPlaylist(count)
            XCTAssertEqual(store.save(playlist, to: url), .saved)
            XCTAssertEqual(store.load(from: url), .loaded(playlist))
        }
        let text = try! String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("Dinner"), "the name is the file name, not stored inside")
        XCTAssertTrue(text.contains("\"version\""))
    }

    func testUnicodeAndEmojiRoundTrip() {                                  // TC-23
        let reference = TrackReference(bookmark: Data([1, 2, 3]), lastKnownPath: "/Musik/Würzburg – 日本語 🎵/été.mp3",
                                       fileName: "été 🎵.mp3")
        let playlist = Playlist(tracks: [Track(id: UUID(), reference: reference)])
        XCTAssertEqual(store.save(playlist, to: url), .saved)
        XCTAssertEqual(store.load(from: url), .loaded(playlist))
    }

    func testLargePlaylistRoundTrip() {                                    // TC-22
        let tracks = (0..<5000).map { index in
            Track(id: UUID(), reference: TrackReference(bookmark: Data(count: 64), lastKnownPath: "/m/\(index).mp3", fileName: "\(index).mp3"))
        }
        let playlist = Playlist(tracks: tracks)
        XCTAssertEqual(store.save(playlist, to: url), .saved)
        XCTAssertEqual(store.load(from: url), .loaded(playlist))
    }

    func testLoadErrors() {                                                // TC-30..33
        XCTAssertEqual(store.load(from: url), .notFound)
        try! Data((0..<256).map { _ in UInt8.random(in: 0...255) }).write(to: url)
        XCTAssertEqual(store.load(from: url), .corrupt)
        try! Data().write(to: url)
        XCTAssertEqual(store.load(from: url), .corrupt)
        try! Data("{\"version\": 99, \"tracks\": []}".utf8).write(to: url)
        XCTAssertEqual(store.load(from: url), .unsupportedVersion(99))
        try! Data("{\"tracks\": []}".utf8).write(to: url)
        XCTAssertEqual(store.load(from: url), .corrupt, "no version")
        try! Data("{\"version\": 1, \"tracks\": [{\"id\": 4}]".utf8).write(to: url)
        XCTAssertEqual(store.load(from: url), .corrupt, "truncated")
    }

    func testUnknownFutureFieldsInSameVersionAreIgnored() {
        let playlist = realPlaylist(2)
        _ = store.save(playlist, to: url)
        var object = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        object["futureField"] = ["a": 1]
        try! JSONSerialization.data(withJSONObject: object).write(to: url)
        XCTAssertEqual(store.load(from: url), .loaded(playlist))
    }

    func testTrackWithMissingAudioFileStillLoads() {                       // TC-34
        let fixture = PlaylistFixture(trackNames: ["track1.mp3"])
        _ = store.save(fixture.playlist, to: url)
        fixture.deleteFile(at: 0)
        XCTAssertEqual(store.load(from: url), .loaded(fixture.playlist))
    }

    // MARK: fault injection

    final class FaultOps: PlaylistFileOperations {
        enum Fault { case none, diskFullOnWrite, interruptBeforeReplace, killBeforeReplace }
        var fault = Fault.none
        let real = SystemPlaylistFileOperations()
        func writeTemporary(_ data: Data, to url: URL) throws {
            if fault == .diskFullOnWrite { throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC),
                                                         userInfo: [NSLocalizedDescriptionKey: "No space left on device"]) }
            try real.writeTemporary(data, to: url)
        }
        func replace(_ destination: URL, with temporary: URL) throws {
            if fault == .interruptBeforeReplace || fault == .killBeforeReplace {
                throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
            }
            try real.replace(destination, with: temporary)
        }
        func remove(_ url: URL) { if fault != .killBeforeReplace { real.remove(url) } }
    }

    func strayFiles() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir.url.path))?.filter { $0 != "Dinner.lplaylist" } ?? []
    }

    func testInterruptionBeforeReplaceLeavesOriginalByteIdentical() {      // TC-24
        let ops = FaultOps()
        let faulty = PlaylistStore(operations: ops)
        let original = realPlaylist(3)
        XCTAssertEqual(faulty.save(original, to: url), .saved)
        let before = try! Data(contentsOf: url)
        ops.fault = .interruptBeforeReplace
        guard case .writeFailed = faulty.save(realPlaylist(5), to: url) else { return XCTFail("expected writeFailed") }
        XCTAssertEqual(try! Data(contentsOf: url), before)
        XCTAssertTrue(strayFiles().isEmpty)
    }

    func testDiskFullKeepsOriginalAndLeavesNoTemporary() {                 // TC-25 / TC-92
        let ops = FaultOps()
        let faulty = PlaylistStore(operations: ops)
        XCTAssertEqual(faulty.save(realPlaylist(3), to: url), .saved)
        let before = try! Data(contentsOf: url)
        ops.fault = .diskFullOnWrite
        guard case .writeFailed(let reason) = faulty.save(realPlaylist(1), to: url) else { return XCTFail() }
        XCTAssertTrue(reason.contains("No space"), reason)
        XCTAssertEqual(try! Data(contentsOf: url), before)
        XCTAssertTrue(strayFiles().isEmpty)
    }

    func testReadOnlyFolderFailsAndKeepsOriginal() throws {                // TC-26
        XCTAssertEqual(store.save(realPlaylist(3), to: url), .saved)
        let before = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.url.path)
        guard case .writeFailed = store.save(realPlaylist(1), to: url) else { return XCTFail("expected writeFailed") }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.url.path)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testStrayTemporaryFromAKilledSaveIsIgnoredOnLoadAndRemovedByNextSave() {   // TC-28 (store level)
        let ops = FaultOps()
        let faulty = PlaylistStore(operations: ops)
        let good = realPlaylist(3)
        XCTAssertEqual(faulty.save(good, to: url), .saved)
        ops.fault = .killBeforeReplace
        _ = faulty.save(realPlaylist(5), to: url)
        XCTAssertEqual(strayFiles().count, 1, "a killed process leaves its temporary behind")
        XCTAssertEqual(store.load(from: url), .loaded(good), "relaunch loads the last good version")
        XCTAssertEqual(store.save(good, to: url), .saved)
        XCTAssertTrue(strayFiles().isEmpty, "removed on the next successful save")
    }

    func testTwoSavesInQuickSuccession() {                                 // TC-27
        let first = realPlaylist(2), second = realPlaylist(4)
        XCTAssertEqual(store.save(first, to: url), .saved)
        XCTAssertEqual(store.save(second, to: url), .saved)
        XCTAssertEqual(store.load(from: url), .loaded(second))
    }

    func testCopyLoadsIdentically() {                                      // TC-29
        let playlist = realPlaylist(3)
        let icloud = dir.makeSubfolder("Mobile Documents/com~apple~CloudDocs")
        XCTAssertEqual(store.save(playlist, to: icloud.appendingPathComponent("Dinner.lplaylist")), .saved)
        let copy = dir.path("Copy.lplaylist")
        try! FileManager.default.copyItem(at: icloud.appendingPathComponent("Dinner.lplaylist"), to: copy)
        XCTAssertEqual(store.load(from: copy), .loaded(playlist))
    }

    func testSaveCreatesOnlyThePlaylistFile() {                            // TC-94
        _ = store.save(realPlaylist(2), to: url)
        XCTAssertEqual(try! FileManager.default.contentsOfDirectory(atPath: dir.url.path), ["Dinner.lplaylist"])
    }
}
