import XCTest
@testable import PlayawayCore

/// Story 39: an open playlist follows its file and never writes a stale copy over a newer one. The state machine is
/// shared; here it is driven over a real temp folder and the real store, with a fake conflict-version seam.
final class FollowedPlaylistTests: XCTestCase {
    private final class FakeConflicts: ConflictVersionReading {
        var versions: [ConflictVersion] = []
        private(set) var resolved: [ConflictVersion] = []
        func unresolvedVersions(of url: URL) -> [ConflictVersion] { versions }
        func markResolved(_ marked: [ConflictVersion], of url: URL) { resolved += marked; versions.removeAll { marked.contains($0) } }
    }

    private var dir: TempDir!
    private var url: URL!
    private var inContainer: (TrackReference) -> Bool = { _ in true }

    override func setUp() {
        dir = TempDir("followed")
        url = dir.path("Dinner.\(playlistFileExtension)")
    }

    private func track(_ name: String, id: UUID = UUID()) -> Track {
        Track(id: id, reference: TrackReference(bookmark: Data(), lastKnownPath: dir.path(name).path, fileName: name))
    }

    private func write(_ playlist: Playlist, to target: URL? = nil, ageSeconds: TimeInterval = 0) {
        let target = target ?? url!
        XCTAssertEqual(PlaylistStore().save(playlist, to: target), .saved)
        if ageSeconds != 0 {
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-ageSeconds)], ofItemAtPath: target.path)
        }
    }

    /// Opens the playlist on disk as a device would, with the fingerprint taken at the read.
    private func opened(conflicts: ConflictVersionReading = FakeConflicts()) -> FollowedPlaylist {
        let store = PlaylistStore()
        guard case .loaded(let playlist) = store.load(from: url) else { fatalError("fixture") }
        return FollowedPlaylist(url: url, playlist: playlist, fingerprint: store.fingerprint(of: url), files: store,
                                conflicts: conflicts, isInContainer: inContainer)
    }

    private func names(_ playlist: Playlist) -> [String] { playlist.tracks.map(\.reference.fileName) }

    /// The other device's save: a different playlist written a moment later, so the fingerprint differs.
    private func otherDeviceWrites(_ playlist: Playlist) {
        write(playlist)
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: url.path)
    }

    // MARK: Following the file

    func testACleanPlaylistTakesTheFilesNewContentsAndSaysSo() {                             // TC-20
        let a = track("a.mp3")
        write(Playlist(tracks: [a]))
        let followed = opened()
        var replacedWith: Playlist?
        followed.onReplaced = { replacedWith = $0 }
        otherDeviceWrites(Playlist(tracks: [a, track("b.mp3")]))
        XCTAssertEqual(followed.fileChanged(), .replaced)
        XCTAssertEqual(names(followed.playlist), ["a.mp3", "b.mp3"])
        XCTAssertEqual(replacedWith, followed.playlist)
        XCTAssertFalse(followed.isEdited)
        XCTAssertEqual(followed.fingerprint, PlaylistStore().fingerprint(of: url), "renewed")
    }

    func testOurOwnSaveEchoedBackIsIgnored() {                                                // TC-21
        write(Playlist(tracks: [track("a.mp3")]))
        let followed = opened()
        var replaced = 0
        followed.onReplaced = { _ in replaced += 1 }
        XCTAssertEqual(followed.fileChanged(), .unchanged)
        XCTAssertEqual(replaced, 0)
    }

    func testAnEditedPlaylistMergesTheFilesChangeOnTopAndStaysEdited() {                     // TC-22
        let a = track("a.mp3"), b = track("b.mp3")
        write(Playlist(tracks: [a, b]))
        let followed = opened()
        followed.edited(Playlist(tracks: [b, a]))                          // my reorder, unsaved
        otherDeviceWrites(Playlist(tracks: [a, b, track("c.mp3")]))        // their add
        XCTAssertEqual(followed.fileChanged(), .merged)
        XCTAssertEqual(names(followed.playlist), ["b.mp3", "c.mp3", "a.mp3"], "my order is the spine (newest); their song lands after its neighbour b")
        XCTAssertTrue(followed.isEdited)
        XCTAssertEqual(followed.save(), .saved)
        guard case .loaded(let onDisk) = PlaylistStore().load(from: url) else { return XCTFail() }
        XCTAssertEqual(names(onDisk), ["b.mp3", "c.mp3", "a.mp3"])
    }

    func testSavingWhenTheFileIsUnchangedWritesAndRenewsTheFingerprint() {                   // TC-23
        let a = track("a.mp3")
        write(Playlist(tracks: [a]))
        let followed = opened()
        followed.edited(Playlist(tracks: [a, track("b.mp3")]))
        XCTAssertTrue(followed.isEdited)
        XCTAssertEqual(followed.save(), .saved)
        XCTAssertFalse(followed.isEdited)
        XCTAssertEqual(followed.fingerprint, PlaylistStore().fingerprint(of: url))
        XCTAssertEqual(followed.fileChanged(), .unchanged, "our own write is not a remote change")
    }

    func testSavingOverANewerFileRebasesFirstSoTheOtherDevicesSongIsNotLost() {               // TC-24
        let a = track("a.mp3"), b = track("b.mp3")
        write(Playlist(tracks: [a]))
        let followed = opened()
        followed.edited(Playlist(tracks: [a, b]))                           // my add
        otherDeviceWrites(Playlist(tracks: [a, track("theirs.mp3")]))       // their add, unseen
        XCTAssertEqual(followed.save(), .saved)
        guard case .loaded(let onDisk) = PlaylistStore().load(from: url) else { return XCTFail() }
        XCTAssertEqual(Set(names(onDisk)), ["a.mp3", "b.mp3", "theirs.mp3"])
        XCTAssertEqual(names(followed.playlist), names(onDisk))
        XCTAssertFalse(followed.isEdited)
    }

    func testSavingOverACorruptFileWritesTheEditSinceThereIsNothingNewerToKeep() throws {     // TC-25
        let a = track("a.mp3")
        write(Playlist(tracks: [a]))
        let followed = opened()
        followed.edited(Playlist(tracks: [a, track("b.mp3")]))
        try Data("garbage".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: url.path)
        XCTAssertEqual(followed.save(), .saved)
        guard case .loaded(let onDisk) = PlaylistStore().load(from: url) else { return XCTFail() }
        XCTAssertEqual(names(onDisk), ["a.mp3", "b.mp3"])
    }

    func testAFileThatIsGoneIsReportedAndNothingIsWritten() throws {                          // TC-26
        write(Playlist(tracks: [track("a.mp3")]))
        let followed = opened()
        var gone = 0
        followed.onGone = { gone += 1 }
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(followed.fileChanged(), .gone)
        XCTAssertEqual(gone, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testACorruptFileLeavesTheOpenPlaylistAloneAndWritesNothing() throws {                // TC-27
        write(Playlist(tracks: [track("a.mp3")]))
        let followed = opened()
        var replaced = 0
        followed.onReplaced = { _ in replaced += 1 }
        try Data("garbage".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: url.path)
        XCTAssertEqual(followed.fileChanged(), .unreadable)
        XCTAssertEqual(replaced, 0)
        XCTAssertEqual(names(followed.playlist), ["a.mp3"])
        XCTAssertEqual(try Data(contentsOf: url), Data("garbage".utf8), "not overwritten")
    }

    func testAChangeThatMergesToTheSamePlaylistIsNotWritten() throws {                        // TC-28
        let a = track("a.mp3")
        write(Playlist(tracks: [a]))
        let followed = opened()
        followed.edited(Playlist(tracks: [a]))                              // an edit that changes nothing
        otherDeviceWrites(Playlist(tracks: [a]))
        let before = try Data(contentsOf: url)
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as! Date
        XCTAssertEqual(followed.fileChanged(), .unchanged, "the same contents, whoever wrote them: nothing to show")
        XCTAssertEqual(followed.save(), .saved)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as! Date, modified, "equal contents: no write")
    }

    // MARK: Conflict versions

    private func conflictVersion(_ playlist: Playlist, name: String, ageSeconds: TimeInterval) -> ConflictVersion {
        let versionURL = dir.path(name)
        write(playlist, to: versionURL, ageSeconds: ageSeconds)
        return ConflictVersion(url: versionURL, modified: Date().addingTimeInterval(-ageSeconds))
    }

    func testOneReadableConflictVersionIsMergedWrittenOnceAndResolved() throws {              // TC-32
        let a = track("a.mp3")
        write(Playlist(tracks: [a, track("mine.mp3")]))
        let conflicts = FakeConflicts()
        let theirs = conflictVersion(Playlist(tracks: [a, track("theirs.mp3")]), name: "v1.lplaylist", ageSeconds: 5)
        conflicts.versions = [theirs]
        let followed = opened(conflicts: conflicts)
        XCTAssertEqual(followed.resolveConflicts(), .merged)
        guard case .loaded(let onDisk) = PlaylistStore().load(from: url) else { return XCTFail() }
        XCTAssertEqual(Set(names(onDisk)), ["a.mp3", "mine.mp3", "theirs.mp3"])
        XCTAssertEqual(conflicts.resolved, [theirs])
        XCTAssertEqual(followed.playlist, onDisk)
        XCTAssertFalse(followed.isEdited)
    }

    func testACorruptConflictVersionIsLeftUnresolvedAndTheReadableOnesMerged() throws {       // TC-33
        let a = track("a.mp3")
        write(Playlist(tracks: [a]))
        let conflicts = FakeConflicts()
        let good = conflictVersion(Playlist(tracks: [a, track("good.mp3")]), name: "good.lplaylist", ageSeconds: 5)
        let badURL = dir.path("bad.lplaylist")
        try Data("garbage".utf8).write(to: badURL)
        let bad = ConflictVersion(url: badURL, modified: Date())
        conflicts.versions = [bad, good]
        let followed = opened(conflicts: conflicts)
        XCTAssertEqual(followed.resolveConflicts(), .merged)
        XCTAssertEqual(Set(names(followed.playlist)), ["a.mp3", "good.mp3"])
        XCTAssertEqual(conflicts.resolved, [good])
        XCTAssertTrue(FileManager.default.fileExists(atPath: badURL.path), "the damaged version is left where it is")
    }

    func testNoConflictVersionsMeansNothingReadOrWritten() throws {                            // TC-34
        write(Playlist(tracks: [track("a.mp3")]))
        let followed = opened()
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as! Date
        XCTAssertEqual(followed.resolveConflicts(), .none)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as! Date, modified)
    }

    func testAConflictThatMergesToTheCurrentFileIsResolvedWithoutAWrite() throws {             // TC-35
        let a = track("a.mp3")
        write(Playlist(tracks: [a]))
        let conflicts = FakeConflicts()
        let same = conflictVersion(Playlist(tracks: [a]), name: "same.lplaylist", ageSeconds: 5)
        conflicts.versions = [same]
        let followed = opened(conflicts: conflicts)
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as! Date
        XCTAssertEqual(followed.resolveConflicts(), .resolvedWithoutChange)
        XCTAssertEqual(conflicts.resolved, [same])
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as! Date, modified)
    }

    func testAFailedWriteResolvesNothingSoTheNextChangeRetries() throws {                      // TC-36
        let a = track("a.mp3")
        write(Playlist(tracks: [a]))
        let conflicts = FakeConflicts()
        let theirs = conflictVersion(Playlist(tracks: [a, track("theirs.mp3")]), name: "v.lplaylist", ageSeconds: 5)
        conflicts.versions = [theirs]
        let followed = opened(conflicts: conflicts)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.url.path) }
        XCTAssertEqual(followed.resolveConflicts(), .writeFailed)
        XCTAssertEqual(conflicts.resolved, [])
    }

    func testTheSameVersionsOnTwoDevicesGiveByteIdenticalFiles() throws {                      // TC-37
        let a = track("a.mp3"), mine = track("mine.mp3"), theirs = track("theirs.mp3")
        let other = TempDir("followed-other")
        let otherURL = other.path("Dinner.\(playlistFileExtension)")
        write(Playlist(tracks: [a, mine]))
        write(Playlist(tracks: [a, mine]), to: otherURL)
        func device(_ target: URL, versionName: String) -> (FollowedPlaylist, FakeConflicts) {
            let conflicts = FakeConflicts()
            let versionURL = target.deletingLastPathComponent().appendingPathComponent(versionName)
            write(Playlist(tracks: [a, theirs]), to: versionURL, ageSeconds: 5)
            conflicts.versions = [ConflictVersion(url: versionURL, modified: Date(timeIntervalSince1970: 1000))]
            let store = PlaylistStore()
            guard case .loaded(let playlist) = store.load(from: target) else { fatalError() }
            return (FollowedPlaylist(url: target, playlist: playlist, fingerprint: store.fingerprint(of: target), files: store,
                                     conflicts: conflicts, isInContainer: inContainer), conflicts)
        }
        let (mac, _) = device(url, versionName: "v.lplaylist")
        let (phone, _) = device(otherURL, versionName: "v.lplaylist")
        XCTAssertEqual(mac.resolveConflicts(), .merged)
        XCTAssertEqual(phone.resolveConflicts(), .merged)
        XCTAssertEqual(try Data(contentsOf: url), try Data(contentsOf: otherURL))
    }

    func testAConflictWhileEditedIncludesTheEditInOneWrite() throws {                           // TC-38
        let a = track("a.mp3")
        write(Playlist(tracks: [a]))
        let conflicts = FakeConflicts()
        let theirs = conflictVersion(Playlist(tracks: [a, track("theirs.mp3")]), name: "v.lplaylist", ageSeconds: 5)
        conflicts.versions = [theirs]
        let followed = opened(conflicts: conflicts)
        followed.edited(Playlist(tracks: [a, track("mine.mp3")]))
        XCTAssertEqual(followed.resolveConflicts(), .merged)
        guard case .loaded(let onDisk) = PlaylistStore().load(from: url) else { return XCTFail() }
        XCTAssertEqual(Set(names(onDisk)), ["a.mp3", "mine.mp3", "theirs.mp3"])
        XCTAssertFalse(followed.isEdited, "the one write carried the edit")
    }

    // MARK: Through the player (TC-29 to TC-31): a reload never touches the engine

    private func audioTrack(_ name: String) -> Track {
        Track(id: UUID(), reference: TrackReference.make(for: dir.copyFixture(name))!)
    }

    private func playerRig(_ followed: FollowedPlaylist) -> (PlaylistPlayer, AVPlaybackEngine) {
        let engine = makeEngine()
        let player = PlaylistPlayer(playlist: { followed.playlist }, settings: PlayModeSettings(store: PlayModeStore(defaults: isolatedDefaults())),
                                    engine: engine, marks: ReadabilityMarkStore(), registry: ActiveSessionRegistry())
        return (player, engine)
    }

    func testAReloadWhileNothingPlaysTouchesNoEngine() {                                        // TC-29
        let a = audioTrack("track1.mp3")
        write(Playlist(tracks: [a]))
        let followed = opened()
        let (_, engine) = playerRig(followed)
        otherDeviceWrites(Playlist(tracks: [a, audioTrack("track2.mp3")]))
        XCTAssertEqual(followed.fileChanged(), .replaced)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertNil(engine.currentURL)
    }

    func testAReloadThatKeepsTheCurrentSongLeavesTheEngineAlone() {                             // TC-30
        let a = audioTrack("track1.mp3"), b = audioTrack("track2.mp3")
        write(Playlist(tracks: [a, b]))
        let followed = opened()
        let (player, engine) = playerRig(followed)
        player.start()
        let playing = engine.currentURL
        XCTAssertEqual(engine.state, .playing)
        otherDeviceWrites(Playlist(tracks: [a, b, audioTrack("track3.mp3")]))
        XCTAssertEqual(followed.fileChanged(), .replaced)
        XCTAssertEqual(engine.currentURL, playing, "the engine was not asked to do anything")
        XCTAssertEqual(engine.state, .playing)
        XCTAssertEqual(player.current?.id, a.id)
        XCTAssertEqual(followed.playlist.tracks.count, 3)
    }

    func testAReloadThatRemovesTheCurrentSongLetsItPlayOnAndThenFollowsTheNewOrder() {          // TC-31
        let a = audioTrack("track1.mp3"), b = audioTrack("track2.mp3")
        write(Playlist(tracks: [a, b]))
        let followed = opened()
        let (player, engine) = playerRig(followed)
        player.start()
        let playing = engine.currentURL
        otherDeviceWrites(Playlist(tracks: [b, audioTrack("track3.mp3")]))          // the other device removed a
        XCTAssertEqual(followed.fileChanged(), .replaced)
        XCTAssertEqual(engine.currentURL, playing, "the removed song plays on to its end")
        XCTAssertEqual(engine.state, .playing)
        player.next()
        XCTAssertEqual(engine.currentURL?.lastPathComponent, "track2.mp3", "the next step follows the new order")
    }
}
