import XCTest
@testable import PlayawayCore

/// A playlist made on the iPhone opens on the Mac (and the other way round) with its songs playable. A song is
/// stored as an alias plus a path made by the device that added it; the other device can follow neither, so the
/// resolver looks in two more places before calling the song missing: the same place inside this device's iCloud
/// Playaway folder, then beside the playlist file by name. A song found that way is resolved but the reference comes
/// back unchanged, so no device rewrites the playlist with a reference only it can use (the ping-pong).
///
/// The phone's container is stood in by a temp folder shaped `.../iCloud~software~away~play/Documents/<Playlist>/`;
/// this device's copy by another; an offloaded song by its `.<name>.icloud` placeholder, as EvictedCloudFileTests does.
@MainActor
final class CrossDevicePlaylistTests: XCTestCase {
    private static let phoneRoot = "/private/var/mobile/Library/Mobile Documents/" + CloudFolder.containerFolderName + "/Documents"

    /// A reference as the other device wrote it: a real alias to a file that is gone (so it cannot resolve here, as a
    /// foreign alias cannot) and a path on the other device.
    private func foreignReference(name: String, playlist: String, in dir: TempDir) -> TrackReference {
        let gone = dir.copyFixture("track1.mp3", as: "gone-\(UUID().uuidString).mp3")
        let alias = try! gone.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        try! FileManager.default.removeItem(at: gone)
        return TrackReference(bookmark: alias, lastKnownPath: Self.phoneRoot + "/\(playlist)/\(name)", fileName: name)
    }

    private func placeholder(for url: URL) {
        let marker = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
        try! Data("placeholder".utf8).write(to: marker)
    }

    /// This device's iCloud Playaway folder, with the playlist's folder inside it.
    private func cloud(in dir: TempDir, playlist: String) -> (documents: URL, playlistFolder: URL) {
        let documents = dir.makeSubfolder("Mobile Documents/\(CloudFolder.containerFolderName)/Documents")
        let folder = documents.appendingPathComponent(playlist)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (documents, folder)
    }

    // MARK: Same device (unchanged behaviour)

    func testASongThisDeviceAddedResolvesByItsAliasWithTheReferenceUnchanged() {          // TC-01
        let dir = TempDir("same")
        let url = dir.copyFixture("track1.mp3")
        let ref = TrackReference.make(for: url)!
        let resolver = TrackResolver(cloudDocuments: dir.makeSubfolder("cloud"))
        let (status, back) = resolver.resolve(ref, besidePlaylistAt: dir.url)
        XCTAssertEqual(status, .resolved(url))
        XCTAssertEqual(back, ref)
    }

    func testASongMovedOnThisDeviceIsFollowedAndRefreshedAsBefore() {                     // TC-02
        let dir = TempDir("same")
        let url = dir.copyFixture("track1.mp3")
        let ref = TrackReference.make(for: url)!
        let moved = dir.makeSubfolder("elsewhere").appendingPathComponent("track1.mp3")
        try! FileManager.default.moveItem(at: url, to: moved)
        let (status, back) = TrackResolver(cloudDocuments: nil).resolve(ref, besidePlaylistAt: dir.url)
        XCTAssertEqual(status, .resolved(moved))
        XCTAssertEqual(back.lastKnownPath, moved.path, "a move on this device still refreshes the reference")
    }

    // MARK: The same place inside this device's iCloud folder

    func testASongThePhoneStoredIsFoundAtTheSamePlaceInThisDevicesCloudFolder() {        // TC-03
        let dir = TempDir("cloud")
        let (documents, folder) = cloud(in: dir, playlist: "Dinner")
        let here = folder.appendingPathComponent("track1.mp3")
        try! FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: here)
        let ref = foreignReference(name: "track1.mp3", playlist: "Dinner", in: dir)
        let (status, back) = TrackResolver(cloudDocuments: documents).resolve(ref)
        XCTAssertEqual(status, .resolved(here))
        XCTAssertEqual(back, ref, "found on the other device's terms: nothing is rewritten")
    }

    func testAnOffloadedSongThePhoneStoredCountsAsPresentInTheCloudFolder() {           // TC-04
        let dir = TempDir("cloud")
        let (documents, folder) = cloud(in: dir, playlist: "Dinner")
        let here = folder.appendingPathComponent("track1.mp3")
        placeholder(for: here)
        let ref = foreignReference(name: "track1.mp3", playlist: "Dinner", in: dir)
        let (status, back) = TrackResolver(cloudDocuments: documents).resolve(ref)
        XCTAssertEqual(status, .resolved(here))
        XCTAssertEqual(back, ref)
    }

    // MARK: Beside the playlist, by name

    func testASongBesideThePlaylistIsFoundByItsName() {                                  // TC-05
        let dir = TempDir("beside")
        let folder = dir.makeSubfolder("Dinner")
        let here = folder.appendingPathComponent("track1.mp3")
        try! FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: here)
        let ref = foreignReference(name: "track1.mp3", playlist: "Dinner", in: dir)
        let (status, back) = TrackResolver(cloudDocuments: dir.makeSubfolder("empty-cloud")).resolve(ref, besidePlaylistAt: folder)
        XCTAssertEqual(status, .resolved(here))
        XCTAssertEqual(back, ref)
    }

    func testAnOffloadedSongBesideThePlaylistCountsAsPresent() {                          // TC-06
        let dir = TempDir("beside")
        let folder = dir.makeSubfolder("Dinner")
        let here = folder.appendingPathComponent("track1.mp3")
        placeholder(for: here)
        let ref = foreignReference(name: "track1.mp3", playlist: "Dinner", in: dir)
        let (status, back) = TrackResolver(cloudDocuments: nil).resolve(ref, besidePlaylistAt: folder)
        XCTAssertEqual(status, .resolved(here))
        XCTAssertEqual(back, ref)
    }

    func testASongNowhereOnThisDeviceIsStillMissing() {                                   // TC-07
        let dir = TempDir("nowhere")
        let (documents, _) = cloud(in: dir, playlist: "Dinner")
        let folder = dir.makeSubfolder("Dinner")
        let ref = foreignReference(name: "track1.mp3", playlist: "Dinner", in: dir)
        let (status, back) = TrackResolver(cloudDocuments: documents).resolve(ref, besidePlaylistAt: folder)
        XCTAssertEqual(status, .missing)
        XCTAssertEqual(back, ref)
    }

    func testAMacPathOutsideTheContainerStillFindsTheSongBesideThePlaylist() {           // TC-08
        let dir = TempDir("music")
        let folder = dir.makeSubfolder("Dinner")
        let here = folder.appendingPathComponent("track1.mp3")
        try! FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: here)
        let ref = TrackReference(bookmark: Data(), lastKnownPath: "/Users/someone/Music/track1.mp3", fileName: "track1.mp3")
        let (status, back) = TrackResolver(cloudDocuments: dir.makeSubfolder("cloud")).resolve(ref, besidePlaylistAt: folder)
        XCTAssertEqual(status, .resolved(here))
        XCTAssertEqual(back, ref)
    }

    func testWithNoPlaylistFolderOnlyTheCloudRouteIsTried() {                             // TC-09
        let dir = TempDir("nofolder")
        let (documents, _) = cloud(in: dir, playlist: "Dinner")
        let ref = foreignReference(name: "track1.mp3", playlist: "Dinner", in: dir)
        XCTAssertEqual(TrackResolver(cloudDocuments: documents).resolve(ref, besidePlaylistAt: nil).0, .missing)
    }

    func testASongWithTheSameNameInAnotherPlaylistsFolderIsNotTaken() {                  // TC-10
        let dir = TempDir("sibling")
        let folder = dir.makeSubfolder("Dinner")
        let sibling = dir.makeSubfolder("Party")
        try! FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: sibling.appendingPathComponent("track1.mp3"))
        let ref = foreignReference(name: "track1.mp3", playlist: "Dinner", in: dir)
        XCTAssertEqual(TrackResolver(cloudDocuments: nil).resolve(ref, besidePlaylistAt: folder).0, .missing,
                       "no guessing across folders")
    }

    func testTheNameMatchIgnoresLetterCaseAsLocateDoes() {                                // TC-11
        let dir = TempDir("case")
        let folder = dir.makeSubfolder("Dinner")
        let here = folder.appendingPathComponent("Track1.MP3")
        try! FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: here)
        let ref = foreignReference(name: "track1.mp3", playlist: "Dinner", in: dir)
        XCTAssertEqual(TrackResolver(cloudDocuments: nil).resolve(ref, besidePlaylistAt: folder).0, .resolved(here))
    }

    func testAnEmptyFileNameNeverMatches() {                                              // TC-12
        let dir = TempDir("empty")
        let folder = dir.makeSubfolder("Dinner")
        try! FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: folder.appendingPathComponent("track1.mp3"))
        let ref = TrackReference(bookmark: Data(), lastKnownPath: Self.phoneRoot + "/Dinner/", fileName: "")
        XCTAssertEqual(TrackResolver(cloudDocuments: nil).resolve(ref, besidePlaylistAt: folder).0, .missing)
    }

    func testWithoutACloudFolderOnThisDeviceTheSongBesideThePlaylistIsStillFound() {     // TC-13
        let dir = TempDir("nocloud")
        let folder = dir.makeSubfolder("Dinner")
        let here = folder.appendingPathComponent("track1.mp3")
        try! FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: here)
        let ref = foreignReference(name: "track1.mp3", playlist: "Dinner", in: dir)
        XCTAssertEqual(TrackResolver(cloudDocuments: nil).resolve(ref, besidePlaylistAt: folder).0, .resolved(here))
    }

    func testAStoredPathInTheTrashIsNotTakenAndTheSearchGoesOn() {                       // TC-14
        let dir = TempDir("trash")
        let trash = dir.makeSubfolder(".Trash")
        let trashed = trash.appendingPathComponent("track1.mp3")
        try! FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: trashed)
        let folder = dir.makeSubfolder("Dinner")
        let here = folder.appendingPathComponent("track1.mp3")
        try! FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: here)
        let ref = TrackReference(bookmark: Data(), lastKnownPath: trashed.path, fileName: "track1.mp3")
        XCTAssertEqual(TrackResolver(cloudDocuments: nil).resolve(ref, besidePlaylistAt: folder).0, .resolved(here))
    }

    // MARK: The container path

    func testTheRelativePathInsideTheContainerIsReadFromAPhoneOrMacPath() {
        XCTAssertEqual(CloudFolder.relativePath(inContainer: Self.phoneRoot + "/Dinner/track1.mp3"), "Dinner/track1.mp3")
        XCTAssertEqual(CloudFolder.relativePath(inContainer: "/Users/j/Library/Mobile Documents/\(CloudFolder.containerFolderName)/Documents/a/b.mp3"), "a/b.mp3")
        XCTAssertNil(CloudFolder.relativePath(inContainer: "/Users/j/Music/b.mp3"))
        XCTAssertNil(CloudFolder.relativePath(inContainer: Self.phoneRoot + "/"), "nothing after the Documents folder")
    }

    func testThisDevicesCloudFolderIsUnderMobileDocumentsWhenItExists() {
        let home = TempDir("home")
        XCTAssertNil(CloudFolder.documentsOnThisDevice(home: home.url), "no iCloud Drive here")
        let documents = home.makeSubfolder("Library/Mobile Documents/\(CloudFolder.containerFolderName)/Documents")
        XCTAssertEqual(CloudFolder.documentsOnThisDevice(home: home.url)?.path, documents.path)
    }

    // MARK: Through the player

    private final class ReferenceRecorder: TrackResolutionReporting {
        var seen: [(UUID, TrackStatus, TrackReference)] = []
        func trackResolved(id: UUID, status: TrackStatus, reference: TrackReference) { seen.append((id, status, reference)) }
    }

    private func player(folder: URL?, track: Track, recorder: ReferenceRecorder) -> (PlaylistPlayer, AVPlaybackEngine) {
        let engine = makeEngine()
        let player = PlaylistPlayer(playlist: { Playlist(tracks: [track]) }, playlistFolder: { folder },
                                    settings: PlayModeSettings(store: PlayModeStore(defaults: isolatedDefaults())),
                                    resolver: TrackResolver(cloudDocuments: nil), engine: engine,
                                    marks: ReadabilityMarkStore(), registry: ActiveSessionRegistry(), reporter: recorder)
        return (player, engine)
    }

    func testThePlayerPlaysASongFoundBesideThePlaylistAndReportsTheReferenceUnchanged() {   // TC-19
        let dir = TempDir("player")
        let folder = dir.makeSubfolder("Dinner")
        let here = folder.appendingPathComponent("track1.mp3")
        try! FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: here)
        let track = Track(id: UUID(), reference: foreignReference(name: "track1.mp3", playlist: "Dinner", in: dir))
        let recorder = ReferenceRecorder()
        let (player, engine) = player(folder: folder, track: track, recorder: recorder)
        player.start()
        XCTAssertEqual(engine.currentURL, here)
        XCTAssertEqual(recorder.seen.count, 1)
        XCTAssertEqual(recorder.seen.first?.1, .resolved(here))
        XCTAssertEqual(recorder.seen.first?.2, track.reference, "nothing for a document to write")
    }

    func testThePlayerRefusesTheSongWhenItDoesNotKnowThePlaylistsFolder() {                 // TC-20
        let dir = TempDir("player")
        let folder = dir.makeSubfolder("Dinner")
        try! FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: folder.appendingPathComponent("track1.mp3"))
        let track = Track(id: UUID(), reference: foreignReference(name: "track1.mp3", playlist: "Dinner", in: dir))
        let recorder = ReferenceRecorder()
        let (player, engine) = player(folder: nil, track: track, recorder: recorder)
        player.start()
        XCTAssertNil(engine.currentURL)
        XCTAssertEqual(recorder.seen.first?.1, .missing)
        XCTAssertEqual(recorder.seen.first?.2, track.reference)
    }
}
