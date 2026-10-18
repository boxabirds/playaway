import XCTest
@testable import PlayawayCore

/// Story 41, reference.match_data: what a reference records to help find the song again on another device.
final class TrackReferenceDetailsTests: XCTestCase {
    let dir = TempDir("details")

    func testMakeRecordsSizeDurationAndFolderName() throws {                       // TC-01
        let folder = dir.url.appendingPathComponent("Mixdowns")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let song = folder.appendingPathComponent("long30.mp3")
        try FileManager.default.copyItem(at: Fixtures.url("long30.mp3"), to: song)
        let ref = try XCTUnwrap(TrackReference.make(for: song))
        XCTAssertEqual(ref.fileSize, Int64(try Data(contentsOf: song).count))
        XCTAssertNil(ref.duration, "adding a song never opens its file (F3): the duration is not read here")
        XCTAssertEqual(ref.folderName, "Mixdowns")
        XCTAssertEqual(ref.groupingFolderName, "Mixdowns")
    }

    func testAStory40ReferenceDecodesWithTheFieldsAbsentAndWritesBackWithout() throws {   // TC-02
        let old = #"{"bookmark":"AQI=","lastKnownPath":"/Users/x/Music/a.mp3","fileName":"a.mp3"}"#
        let ref = try JSONDecoder().decode(TrackReference.self, from: Data(old.utf8))
        XCTAssertNil(ref.fileSize); XCTAssertNil(ref.duration); XCTAssertNil(ref.folderName)
        XCTAssertEqual(ref.groupingFolderName, "Music", "from the stored path when nothing was recorded")
        let json = String(decoding: try JSONEncoder().encode(ref), as: UTF8.self)
        XCTAssertFalse(json.contains("fileSize") || json.contains("duration") || json.contains("folderName"), json)
    }

    func testTheFieldsRoundTrip() throws {                                          // TC-03
        let ref = TrackReference(bookmark: Data([1]), lastKnownPath: "/x/a.mp3", fileName: "a.mp3", fileSize: 1234, duration: 61.5, folderName: "Live")
        XCTAssertEqual(try JSONDecoder().decode(TrackReference.self, from: JSONEncoder().encode(ref)), ref)
    }

    func testAnEmptyFileHasASizeOfZeroAndNoDuration() throws {                      // TC-04
        let song = dir.url.appendingPathComponent("empty.mp3")
        try Data().write(to: song)
        let ref = try XCTUnwrap(TrackReference.make(for: song))
        XCTAssertEqual(ref.fileSize, 0)
        XCTAssertNil(ref.duration)
    }

    func testReadingAStory40PlaylistFromDiskRewritesNothing() throws {              // TC-05
        let file = dir.url.appendingPathComponent("Old.\(playlistFileExtension)")
        let old = #"{"version":1,"tracks":[{"id":"7C5E1F0A-0D3B-4C57-9E36-0F1F4A6E2B11","reference":{"bookmark":"AQI=","lastKnownPath":"/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Mixdowns/a.mp3","fileName":"a.mp3"}}]}"#
        try Data(old.utf8).write(to: file)
        let before = try Data(contentsOf: file)
        guard case .loaded(let playlist) = PlaylistStore().load(from: file) else { return XCTFail("did not load") }
        XCTAssertNil(playlist.tracks[0].reference.fileSize)
        XCTAssertEqual(playlist.tracks[0].reference.portableLocation, .iCloudDrive("Mixdowns/a.mp3"))
        XCTAssertEqual(try Data(contentsOf: file), before, "loading does not rewrite the file")
    }

    /// F3 of the audit: adding a song read its audio header, on the main thread, for every file. A file iCloud has not
    /// downloaded can block that read, and 300 files pay 300 opens before the list updates. A named pipe stands in for a
    /// file that blocks when it is opened: making a reference must return without opening it at all.
    func testMakingAReferenceNeverOpensTheFile() throws {
        let fifo = dir.url.appendingPathComponent("blocks-when-opened.mp3")
        XCTAssertEqual(mkfifo(fifo.path, 0o644), 0)
        let finished = DispatchSemaphore(value: 0)
        var made: TrackReference?
        DispatchQueue.global().async { made = TrackReference.make(for: fifo); finished.signal() }
        let returned = finished.wait(timeout: .now() + 3) == .success
        if !returned {                                  // release the blocked reader so the test can end
            let writer = open(fifo.path, O_WRONLY | O_NONBLOCK); if writer >= 0 { close(writer) }
            _ = finished.wait(timeout: .now() + 3)
        }
        XCTAssertTrue(returned, "make(for:) blocked: it opened the file")
        XCTAssertEqual(made?.fileName, "blocks-when-opened.mp3")
    }

    func testAddingSongsNeverOpensThem() throws {
        let fifo = dir.url.appendingPathComponent("blocks-when-opened.wav")
        XCTAssertEqual(mkfifo(fifo.path, 0o644), 0)
        let finished = DispatchSemaphore(value: 0)
        var result: AddResult?
        DispatchQueue.global().async { result = adding([fifo], to: Playlist(), classifier: AcceptingClassifier()); finished.signal() }
        let returned = finished.wait(timeout: .now() + 3) == .success
        if !returned { let writer = open(fifo.path, O_WRONLY | O_NONBLOCK); if writer >= 0 { close(writer) }; _ = finished.wait(timeout: .now() + 3) }
        XCTAssertTrue(returned, "adding blocked on a file it should not open")
        XCTAssertEqual(result?.added.count, 1)
    }

    private struct AcceptingClassifier: FormatClassifying {
        func classify(_ url: URL) -> FormatClassification { .supported(.wav) }
    }
}
