import XCTest
import AppKit
@testable import LocalPlayer
@testable import PlayawayCore

/// Story 39 on the Mac: an open playlist document follows its file. Another device's save (stood in by a
/// coordinated write from a background thread, as iCloud's would arrive) shows within moments, the playing song is
/// untouched, an unsaved edit is merged on top rather than lost, the document's own autosave is not taken for a
/// remote change, and a deleted or damaged file changes nothing on screen and writes nothing.
@MainActor
final class RemoteChangeDocumentTests: XCTestCase {
    var app: TestApp!
    let dir = TempDir("remote")
    private var fixtures: [PlaylistFixture] = []

    override func setUp() async throws { app = TestApp() }
    override func tearDown() async throws { app.tearDown() }

    private func open(_ names: [String] = ["track1.mp3", "track2.mp3"]) -> (PlaylistDocument, PlaylistFixture, URL) {
        let fixture = PlaylistFixture(trackNames: names)
        fixtures.append(fixture)
        let url = dir.path("Dinner.\(playlistFileExtension)")
        return (app.openSaved(fixture.playlist, at: url), fixture, url)
    }

    /// The other device's save: written through the file coordinator off the main thread, dated a moment later.
    private func otherDeviceWrites(_ playlist: Playlist, to url: URL) {
        var done = false
        DispatchQueue.global().async {
            _ = PlaylistStore().save(playlist, to: url)
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: url.path)
            DispatchQueue.main.async { done = true }
        }
        spin { done }
    }

    private func names(_ doc: PlaylistDocument) -> [String] { doc.playlist.tracks.map(\.reference.fileName) }

    func testTheOpenPlaylistShowsAnotherDevicesChangeWhileTheSongKeepsPlaying() throws {      // TC-40
        let (doc, fixture, url) = open()
        doc.player.start()
        let playing = app.services.engine.currentURL
        XCTAssertNotNil(playing)
        let extra = fixture.dir.copyFixture("track3.mp3")
        otherDeviceWrites(Playlist(tracks: fixture.tracks + [Track(id: UUID(), reference: TrackReference.make(for: extra)!)]), to: url)
        spin { doc.playlist.tracks.count == 3 }
        XCTAssertEqual(names(doc), ["track1.mp3", "track2.mp3", "track3.mp3"])
        XCTAssertEqual(app.services.engine.currentURL, playing, "the song plays on")
        XCTAssertFalse(doc.isDocumentEdited, "nothing of ours is unsaved")
        spin { doc.statuses.status(of: doc.playlist.tracks[2].id) != nil }
        XCTAssertEqual(doc.statuses.status(of: doc.playlist.tracks[2].id), .resolved(extra), "the new row is resolved, so it plays")
    }

    func testAnUnsavedEditIsMergedOnTopOfTheChangeAndTheMergeIsWhatGetsSaved() throws {        // TC-41
        let (doc, fixture, url) = open(["track1.mp3", "track2.mp3", "track3.mp3"])
        let window = app.window(of: doc)
        _ = window.reorder(rows: [2], toBefore: 0)                             // my edit: track3 first
        XCTAssertEqual(names(doc), ["track3.mp3", "track1.mp3", "track2.mp3"])
        let extra = fixture.dir.copyFixture("track4.mp3")
        otherDeviceWrites(Playlist(tracks: fixture.tracks + [Track(id: UUID(), reference: TrackReference.make(for: extra)!)]), to: url)
        spin { doc.playlist.tracks.count == 4 }
        XCTAssertEqual(names(doc), ["track3.mp3", "track4.mp3", "track1.mp3", "track2.mp3"], "my order is the spine; their song lands after its neighbour track3")
        waitForAutosave(doc)
        guard case .loaded(let onDisk) = PlaylistStore().load(from: url) else { return XCTFail() }
        XCTAssertEqual(onDisk.tracks.map(\.reference.fileName), ["track3.mp3", "track4.mp3", "track1.mp3", "track2.mp3"], "the file holds both")
    }

    func testTheDocumentsOwnAutosaveIsNotTakenForARemoteChange() throws {                      // TC-42
        let (doc, fixture, url) = open()
        var publishes = 0
        let subscription = doc.changes.sink { publishes += 1 }
        defer { subscription.cancel() }
        doc.addFiles([fixture.dir.copyFixture("track3.mp3")])
        let afterEdit = publishes
        waitForAutosave(doc)
        spin(timeout: 0.5) { false }
        XCTAssertEqual(publishes, afterEdit, "the autosave's own write echoes back as nothing")
        XCTAssertEqual(names(doc), ["track1.mp3", "track2.mp3", "track3.mp3"])
        guard case .loaded(let onDisk) = PlaylistStore().load(from: url) else { return XCTFail() }
        XCTAssertEqual(onDisk, doc.playlist)
    }

    func testADeletedFileLeavesTheOpenPlaylistAsItWasAndWritesNothing() throws {               // TC-43
        let (doc, _, url) = open()
        var done = false
        DispatchQueue.global().async {
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { try? FileManager.default.removeItem(at: $0) }
            DispatchQueue.main.async { done = true }
        }
        spin { done }
        spin(timeout: 0.5) { false }
        XCTAssertEqual(names(doc), ["track1.mp3", "track2.mp3"], "the person still sees their list")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "nothing was written back")
    }

    func testADamagedFileChangesNothingOnScreenAndIsNotOverwritten() throws {                    // TC-44
        let (doc, _, url) = open()
        var done = false
        DispatchQueue.global().async {
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &error) { try? Data("garbage".utf8).write(to: $0) }
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: url.path)
            DispatchQueue.main.async { done = true }
        }
        spin { done }
        spin(timeout: 0.5) { false }
        XCTAssertEqual(names(doc), ["track1.mp3", "track2.mp3"])
        XCTAssertEqual(try Data(contentsOf: url), Data("garbage".utf8), "not written over")
        XCTAssertTrue(app.notices.shown.isEmpty, "no message for a file we simply cannot read yet")
    }

    func testAScriptSeesTheNewListAfterARemoteChange() throws {                                  // TC-45
        let (doc, fixture, url) = open()
        let actions = AppActions(services: app.services)
        actions.isReady = { true }
        XCTAssertThrowsError(try actions.playTrack(3, inPlaylist: "Dinner"), "no third track yet")
        let extra = fixture.dir.copyFixture("track3.mp3")
        otherDeviceWrites(Playlist(tracks: fixture.tracks + [Track(id: UUID(), reference: TrackReference.make(for: extra)!)]), to: url)
        spin { doc.playlist.tracks.count == 3 }
        XCTAssertNoThrow(try actions.playTrack(3, inPlaylist: "Dinner"), "the script plays the song the other device added")
        XCTAssertEqual(app.services.engine.currentURL, extra)
    }
}
