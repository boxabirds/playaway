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
        XCTAssertEqual(try XCTUnwrap(ref.duration), 30, accuracy: 1.0)
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
}
