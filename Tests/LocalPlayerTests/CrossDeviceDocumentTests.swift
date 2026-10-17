import XCTest
import AppKit
@testable import LocalPlayer
@testable import PlayawayCore

/// A playlist folder as the iPhone writes it (the playlist file beside its songs, every reference made on the phone)
/// opens on the Mac with every song present and plays, and the file is left exactly as it was: nothing is relinked,
/// nothing is marked changed, nothing is autosaved. Story 37, TC-15 to TC-18. The real document, store, resolver and
/// scripting objects; the engine is the recording backend, so nothing is heard.
@MainActor
final class CrossDeviceDocumentTests: XCTestCase {
    private static let phoneRoot = "/private/var/mobile/Library/Mobile Documents/" + CloudFolder.containerFolderName + "/Documents"
    var app: TestApp!
    let dir = TempDir("crossdevice")

    override func tearDown() async throws { app?.tearDown() }

    /// A reference as the phone wrote it: an alias this Mac cannot follow and a path on the phone.
    private func foreignReference(name: String, playlist: String) -> TrackReference {
        let gone = dir.copyFixture("track1.mp3", as: "gone-\(UUID().uuidString).mp3")
        let alias = try! gone.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        try! FileManager.default.removeItem(at: gone)
        return TrackReference(bookmark: alias, lastKnownPath: Self.phoneRoot + "/\(playlist)/\(name)", fileName: name)
    }

    /// The phone's layout: `<root>/<Playlist>/<Playlist>.lplaylist` beside the songs (or, with `songsBeside` false,
    /// the file alone in its folder).
    private func phoneWrittenPlaylist(named name: String, songs: [String], in root: URL, songsBeside: Bool = true)
        -> (file: URL, folder: URL, playlist: Playlist) {
        let folder = root.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if songsBeside {
            for song in songs { try! FileManager.default.copyItem(at: Fixtures.url(song), to: folder.appendingPathComponent(song)) }
        }
        let playlist = Playlist(tracks: songs.map { Track(id: UUID(), reference: foreignReference(name: $0, playlist: name)) })
        let file = folder.appendingPathComponent("\(name).\(playlistFileExtension)")
        XCTAssertEqual(PlaylistStore().save(playlist, to: file), .saved)
        return (file, folder, playlist)
    }

    private func fingerprint(_ url: URL) -> (bytes: Data, modified: Date) {
        let bytes = try! Data(contentsOf: url)
        let modified = try! FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as! Date
        return (bytes, modified)
    }

    /// Opens through the real controller and waits for the first resolution pass.
    private func open(_ file: URL) -> PlaylistDocument {
        var opened: NSDocument?
        var done = false
        app.controller.openDocument(withContentsOf: file, display: true) { document, _, _ in opened = document; done = true }
        spin { done }
        let document = opened as! PlaylistDocument
        var resolved = false
        document.resolveStatuses { resolved = true }
        spin { resolved }
        return document
    }

    private func assertUntouched(_ file: URL, since before: (bytes: Data, modified: Date), _ message: String) {
        spin(timeout: 0.5) { false }                                // an autosave, were one scheduled, would show by now
        let after = fingerprint(file)
        XCTAssertEqual(after.bytes, before.bytes, message)
        XCTAssertEqual(after.modified, before.modified, message)
    }

    func testAPhoneWrittenPlaylistFolderOpensWithEverySongPresentAndTheFileUntouched() {       // TC-15
        app = TestApp(resolver: TrackResolver(cloudDocuments: nil))
        let (file, folder, playlist) = phoneWrittenPlaylist(named: "Dinner", songs: ["track1.mp3", "track2.mp3"], in: dir.url)
        let before = fingerprint(file)
        let document = open(file)
        for track in playlist.tracks {
            XCTAssertEqual(document.statuses.status(of: track.id), .resolved(folder.appendingPathComponent(track.reference.fileName)),
                           "\(track.reference.fileName) is found beside the playlist")
        }
        XCTAssertEqual(document.playlist, playlist, "no reference was rewritten")
        XCTAssertFalse(document.isDocumentEdited)
        assertUntouched(file, since: before, "opening never writes the file")
    }

    func testSongsAtTheSamePlaceInTheMacsCloudFolderAreFoundWhenNoneAreBesideThePlaylist() {   // TC-16
        let macCloud = dir.makeSubfolder("Library/Mobile Documents/\(CloudFolder.containerFolderName)/Documents")
        let songsFolder = macCloud.appendingPathComponent("Dinner")
        try! FileManager.default.createDirectory(at: songsFolder, withIntermediateDirectories: true)
        for song in ["track1.mp3", "track2.mp3"] {
            try! FileManager.default.copyItem(at: Fixtures.url(song), to: songsFolder.appendingPathComponent(song))
        }
        app = TestApp(resolver: TrackResolver(cloudDocuments: macCloud))
        let (file, _, playlist) = phoneWrittenPlaylist(named: "Dinner", songs: ["track1.mp3", "track2.mp3"],
                                                       in: dir.makeSubfolder("elsewhere"), songsBeside: false)
        let before = fingerprint(file)
        let document = open(file)
        for track in playlist.tracks {
            XCTAssertEqual(document.statuses.status(of: track.id), .resolved(songsFolder.appendingPathComponent(track.reference.fileName)))
        }
        XCTAssertEqual(document.playlist, playlist)
        XCTAssertFalse(document.isDocumentEdited)
        assertUntouched(file, since: before, "a find in the cloud folder never writes the file")
    }

    func testASongRemovedFromTheFolderIsMissingAloneAndLocateStillReconnectsIt() {              // TC-17
        app = TestApp(resolver: TrackResolver(cloudDocuments: nil))
        let (file, folder, playlist) = phoneWrittenPlaylist(named: "Dinner", songs: ["track1.mp3", "track2.mp3"], in: dir.url)
        let elsewhere = dir.makeSubfolder("elsewhere").appendingPathComponent("track2.mp3")
        try! FileManager.default.moveItem(at: folder.appendingPathComponent("track2.mp3"), to: elsewhere)
        let document = open(file)
        XCTAssertEqual(document.statuses.status(of: playlist.tracks[0].id), .resolved(folder.appendingPathComponent("track1.mp3")))
        XCTAssertEqual(document.statuses.status(of: playlist.tracks[1].id), .missing, "only the song that is nowhere is missing")
        let result = document.relinker.relink(trackID: playlist.tracks[1].id, to: elsewhere, in: document)
        XCTAssertEqual(result, .relinked([playlist.tracks[1].id]))
        XCTAssertEqual(document.statuses.status(of: playlist.tracks[1].id), .resolved(elsewhere))
        XCTAssertNotEqual(document.playlist.tracks[1].reference, playlist.tracks[1].reference, "Locate writes a reference, as before")
    }

    func testTheFoundSongPlaysAndTheScriptSeesItAsPresentAndTheFileStaysUntouched() throws {   // TC-18
        app = TestApp(resolver: TrackResolver(cloudDocuments: nil))
        let (file, folder, playlist) = phoneWrittenPlaylist(named: "Dinner", songs: ["track1.mp3"], in: dir.url)
        let before = fingerprint(file)
        let document = open(file)
        document.player.start()
        XCTAssertEqual(app.services.engine.currentURL, folder.appendingPathComponent("track1.mp3"), "the song beside the playlist plays")
        let actions = AppActions(services: app.services)
        actions.isReady = { true }                                   // as the scripting tests do: the first window is up
        XCTAssertThrowsError(try actions.locateTrack(1, inPlaylist: "Dinner", withFile: folder.appendingPathComponent("track1.mp3").path)) { error in
            XCTAssertTrue("\(error)".contains("not missing"), "the script sees the track as present: \(error)")
        }
        XCTAssertEqual(document.playlist, playlist)
        XCTAssertFalse(document.isDocumentEdited)
        assertUntouched(file, since: before, "playing never writes the file")
    }
}
