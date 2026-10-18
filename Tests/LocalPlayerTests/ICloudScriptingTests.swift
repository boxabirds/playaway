import XCTest
import AppKit
@testable import LocalPlayer
@testable import PlayawayCore

/// Story 22: everything iCloud a person can do in the playlist window can be done by script with the same result,
/// the same refusals and numbered errors; reading state changes nothing; a scripted play of a song not on this Mac
/// starts the same download as the window, waits until it plays, and errors if the download fails. A temp folder
/// stands in for the Playaway folder and a scripted provider for iCloud; the Apple event layer is not exercised
/// (the commands' argument extraction is one line each and the sdef is checked as text).
@MainActor
final class ICloudScriptingTests: XCTestCase {
    var app: TestApp!
    var actions: AppActions!
    var songs: ScriptedCloudSongs!
    let cloud = TempDir("scriptcloud")
    let docs = TempDir("scriptdocs")
    private var fixtures: [PlaylistFixture] = []

    override func setUp() async throws { makeApp(root: cloud.url) }
    override func tearDown() async throws { app.tearDown() }

    private func makeApp(root: URL?) {
        songs = ScriptedCloudSongs(root: { root })
        app = TestApp(cloudRoot: { root }, cloudSongs: songs)
        actions = AppActions(services: app.services)
        actions.isReady = { true }
        actions.defaultSaveDirectory = docs.url
    }

    /// A synced playlist with a song in its folder and here, a song outside iCloud, and a song in iCloud but not here.
    private func openSynced(_ name: String = "Dinner") throws -> (doc: PlaylistDocument, inside: URL, outside: URL, absent: URL) {
        let folder = cloud.url.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let inside = folder.appendingPathComponent("track1.mp3"), absent = folder.appendingPathComponent("track3.mp3")
        try FileManager.default.copyItem(at: Fixtures.url("track1.mp3"), to: inside)
        try FileManager.default.copyItem(at: Fixtures.url("track3.mp3"), to: absent)
        let outsideFixture = PlaylistFixture(trackNames: ["track2.mp3"])
        fixtures.append(outsideFixture)
        let outside = outsideFixture.urls[0]
        songs.notOnDevice.insert(absent.canonicalPath)
        let tracks = [inside, outside, absent].map { Track(id: UUID(), reference: TrackReference.make(for: $0)!) }
        let doc = app.openSaved(Playlist(tracks: tracks), at: folder.appendingPathComponent("\(name).\(playlistFileExtension)"))
        var done = false; doc.resolveStatuses { done = true }; spin { done }
        app.window(of: doc).reload()
        return (doc, inside, outside, absent)
    }

    private func outside(_ names: [String]) -> PlaylistFixture {
        let fixture = PlaylistFixture(trackNames: names)
        fixtures.append(fixture)
        return fixture
    }

    private func paths(_ doc: PlaylistDocument) -> [String] { doc.playlist.tracks.map { URL(fileURLWithPath: $0.reference.lastKnownPath).canonicalPath } }
    private func cell(_ doc: PlaylistDocument, _ row: Int) -> TrackCellView {
        app.window(of: doc).tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as! TrackCellView
    }
    private func expectFailure(_ number: Int?, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) -> ScriptFailure? {
        do { try body(); XCTFail("expected a refusal", file: file, line: line); return nil } catch let failure as ScriptFailure {
            if let number { XCTAssertEqual(failure.number, number, failure.message, file: file, line: line) }
            XCTAssertFalse(failure.message.isEmpty, "a plain-language message", file: file, line: line)
            return failure
        } catch { XCTFail("unexpected \(error)", file: file, line: line); return nil }
    }

    // MARK: Sync playlist returns the report (prd.icloud.script.report, TC-26)

    func testSyncPlaylistReturnsThePathAndTheCountsTheOnScreenBoxShows() throws {
        let fixture = outside(["track1.mp3", "track2.mp3"])
        let doc = app.openSaved(fixture.playlist, at: docs.path("Morning.\(playlistFileExtension)"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.dir.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.dir.url.path) }
        let report = try actions.syncPlaylist("Morning", answering: "move", files: "move to iCloud")
        XCTAssertEqual(URL(fileURLWithPath: report.path).canonicalPath, cloud.url.appendingPathComponent("Morning/Morning.\(playlistFileExtension)").canonicalPath)
        XCTAssertEqual([report.moved, report.copied, report.copiedInstead, report.failed], [0, 0, 2, 0], "read-only songs were copied instead of moved: counted as copied instead, not as copies")
        XCTAssertEqual(report.copiedInstead, 2, "the number the on-screen box shows")
        XCTAssertEqual(doc.sync.state, .on)
    }

    // MARK: Add track with a files answer (prd.icloud.script.add_track, TC-09, TC-10, TC-21, TC-32)

    func testAddTrackWithAFilesAnswerGivesTheSameResultAsADropWithThatAnswer() throws {
        for (answer, token) in [(FilesChoice.copyToICloud, "copy to iCloud"), (.moveToICloud, "move to iCloud"), (.doNothing, "add without syncing")] {
            let byDrop = try openSynced("Drop-\(token)")
            let dropped = outside(["tone.wav"])
            let window = app.window(of: byDrop.doc)
            window.askFilesChoice = { answer }
            window.dropFiles(dropped.urls)
            spin { window.intakeFinished }
            let byScript = try openSynced("Script-\(token)")
            let added = outside(["tone.wav"])
            try actions.addTrack(path: added.urls[0].path, toPlaylist: "Script-\(token)", files: token)
            let relative = { (doc: PlaylistDocument) -> [String] in
                doc.playlist.tracks.map { track in
                    let path = URL(fileURLWithPath: track.reference.lastKnownPath).canonicalPath
                    return (path.hasPrefix(doc.folder!.canonicalPath) ? "folder/" : "outside/") + track.reference.fileName
                }
            }
            XCTAssertEqual(relative(byScript.doc), relative(byDrop.doc), token)
            XCTAssertEqual(FileManager.default.fileExists(atPath: added.urls[0].path), FileManager.default.fileExists(atPath: dropped.urls[0].path), token)
            XCTAssertEqual(try actions.trackICloudStates("Script-\(token)"), try actions.trackICloudStates("Drop-\(token)"), token)
        }
    }

    func testAddTrackIntoAnUnsyncedPlaylistBehavesAsTodayWhateverTheFilesAnswer() throws {
        let fixture = outside(["track1.mp3"])
        let doc = app.openSaved(Playlist(), at: docs.path("Local.\(playlistFileExtension)"))
        let added = outside(["tone.wav"])
        try actions.addTrack(path: added.urls[0].path, toPlaylist: "Local", files: "move to iCloud")
        XCTAssertEqual(paths(doc), [added.urls[0].canonicalPath], "added where it is")
        XCTAssertTrue(FileManager.default.fileExists(atPath: added.urls[0].path), "nothing moved")
        XCTAssertFalse(try actions.isPlaylistSynced("Local"))
        _ = fixture
    }

    func testAddTrackWithAnAnswerThatIsNotAllowedIsRefusedWith1005AndChangesNothing() throws {
        let synced = try openSynced()
        let before = paths(synced.doc)
        let added = outside(["tone.wav"])
        for bad in ["do nothing", "maybe"] {
            _ = expectFailure(ScriptError.invalidParameter) { try actions.addTrack(path: added.urls[0].path, toPlaylist: "Dinner", files: bad) }
        }
        XCTAssertEqual(paths(synced.doc), before, "nothing added")
        XCTAssertTrue(FileManager.default.fileExists(atPath: added.urls[0].path))
    }

    func testAddTrackWithNoFilesAnswerIntoASyncedPlaylistAddsWithoutSyncing() throws {
        let synced = try openSynced()
        let added = outside(["tone.wav"])
        try actions.addTrack(path: added.urls[0].path, toPlaylist: "Dinner")
        XCTAssertEqual(paths(synced.doc).last, added.urls[0].canonicalPath, "as the sync playlist command does with no files answer")
        XCTAssertEqual(try actions.trackICloudStates("Dinner").last, "not in iCloud")
    }

    // MARK: Reading state (prd.icloud.script.read_state, TC-12, TC-14, TC-30, TC-31, TC-41, TC-82)

    func testReadingSyncAndTrackStatesMatchesTheWindowAndChangesNothing() throws {
        let synced = try openSynced()
        let doc = synced.doc
        let before = (paths(doc), app.services.engine.currentURL, songs.started)
        XCTAssertTrue(try actions.isPlaylistSynced("Dinner"))
        XCTAssertTrue(doc.scriptICloudSync, "the property the dictionary exposes")
        XCTAssertEqual(try actions.trackICloudStates("Dinner"), ["in iCloud", "not in iCloud", "in iCloud"], "location only: the absent song is in iCloud")
        XCTAssertEqual(doc.scriptTrackICloudStates, ["in iCloud", "not in iCloud", "in iCloud"])
        XCTAssertEqual([cell(doc, 0).cloudKind, cell(doc, 1).cloudKind, cell(doc, 2).cloudKind], [.outline, .crossedOut, .outline], "what the window shows")
        XCTAssertEqual(before.0, paths(doc)); XCTAssertEqual(before.1, app.services.engine.currentURL); XCTAssertEqual(before.2, songs.started)
        // A playlist outside iCloud: not synced, and its songs are reported by where they are.
        let local = outside(["track1.mp3"])
        let localDoc = app.openSaved(local.playlist, at: docs.path("Local.\(playlistFileExtension)"))
        XCTAssertFalse(try actions.isPlaylistSynced("Local"))
        XCTAssertFalse(localDoc.scriptICloudSync)
        XCTAssertEqual(try actions.trackICloudStates("Local"), ["not in iCloud"])
    }

    func testTrackStatesOfAnEmptyPlaylistIsAnEmptyListAndAnUnknownPlaylistIs1001() throws {
        let doc = app.openSaved(Playlist(), at: docs.path("Empty.\(playlistFileExtension)"))
        XCTAssertEqual(try actions.trackICloudStates("Empty"), [])
        XCTAssertEqual(doc.scriptTrackICloudStates, [])
        _ = expectFailure(ScriptError.noSuchPlaylist) { _ = try actions.trackICloudStates("Nowhere") }
        _ = expectFailure(ScriptError.noSuchPlaylist) { _ = try actions.isPlaylistSynced("Nowhere") }
    }

    func testNoScriptPropertyReportsDownloadState() throws {
        let text = try String(contentsOf: sdefURL, encoding: .utf8).lowercased()
        for word in ["downloading", "downloaded", "download failed", "turn off", "delete"] {
            XCTAssertFalse(text.contains("name=\"\(word)"), "no property or command named \(word)")
        }
        XCTAssertTrue(text.contains("name=\"icloud sync\""))
        XCTAssertTrue(text.contains("name=\"track icloud states\""))
        XCTAssertTrue(text.contains("name=\"sync report\""), "the record the sync command returns")
        XCTAssertTrue(text.contains("<cocoa key=\"filesanswer\"/>"))
        XCTAssertTrue(PlaylistDocument.instancesRespond(to: NSSelectorFromString("scriptICloudSync")))
        XCTAssertTrue(PlaylistDocument.instancesRespond(to: NSSelectorFromString("scriptTrackICloudStates")))
    }

    // MARK: Errors (prd.icloud.script.errors, TC-56)

    func testTheErrorTableKeepsItsNumbersAndHasNoDuplicates() {
        let table = [ScriptError.noSuchPlaylist, ScriptError.nothingPlaying, ScriptError.unsupportedFile, ScriptError.fileNotFound,
                     ScriptError.invalidParameter, ScriptError.noSuchTrack, ScriptError.locateFailed, ScriptError.notReady,
                     ScriptError.iCloudUnavailable, ScriptError.syncFailed, ScriptError.downloadFailed]
        XCTAssertEqual(table, Array(1001...1011))
        XCTAssertEqual(Set(table).count, table.count)
        XCTAssertTrue(ScriptFailure.iCloudUnavailable.message.hasPrefix("iCloud unavailable"))
        XCTAssertTrue(ScriptFailure.iCloudUnavailable.message.contains(ICloudAvailability.unavailableReason), "the window's one-line reason")
    }

    // MARK: iCloud unavailable (prd.icloud.script.unavailable, TC-50 to TC-54, TC-58, TC-61)

    func testWhileICloudIsUnavailableSyncIsRefusedWith1009WithTheWindowsReasonAndReadsStillWork() throws {
        app.tearDown()
        makeApp(root: nil)
        let fixture = outside(["track1.mp3", "track2.mp3"])
        let doc = app.openSaved(fixture.playlist, at: docs.path("Morning.\(playlistFileExtension)"))
        let before = paths(doc)
        let failure = expectFailure(ScriptError.iCloudUnavailable) { _ = try actions.syncPlaylist("Morning", answering: "move", files: "copy") }
        let window = app.window(of: doc)
        XCTAssertFalse(window.syncButton.isEnabled, "the window's switch is disabled")
        XCTAssertEqual(window.syncReason.stringValue, ICloudAvailability.unavailableReason)
        XCTAssertTrue(failure?.message.contains(window.syncReason.stringValue) == true, "the same one-line reason by both routes")
        XCTAssertEqual(paths(doc), before, "nothing moved")
        for url in fixture.urls { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) }
        XCTAssertFalse(try actions.isPlaylistSynced("Morning"), "reads still work")
        XCTAssertEqual(try actions.trackICloudStates("Morning"), ["not in iCloud", "not in iCloud"])
        // Add track: an answer that would move or copy into iCloud is refused; add without syncing works as today.
        let added = outside(["tone.wav"])
        _ = expectFailure(ScriptError.iCloudUnavailable) { try actions.addTrack(path: added.urls[0].path, toPlaylist: "Morning", files: "copy to iCloud") }
        XCTAssertEqual(paths(doc), before)
        try actions.addTrack(path: added.urls[0].path, toPlaylist: "Morning")
        XCTAssertEqual(paths(doc).count, 3)
        // An unknown playlist and a not-ready app win over 1009.
        _ = expectFailure(ScriptError.noSuchPlaylist) { _ = try actions.syncPlaylist("Nowhere", answering: "move") }
        actions.isReady = { false }
        _ = expectFailure(ScriptError.notReady) { _ = try actions.syncPlaylist("Morning", answering: "move") }
    }

    // MARK: Scripted play of a song not on this Mac (prd.icloud.script.play_download, TC-70 to TC-81)

    func testPlayingASongNotOnThisMacByScriptStartsTheSameDownloadWaitsAndReturnsWhenItPlays() throws {
        let synced = try openSynced()
        let doc = synced.doc
        var sawThePie = false
        let timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [self] _ in
            sawThePie = cell(doc, 2).cloudKind == .pieDownload                           // the window shows the download meanwhile
            XCTAssertEqual(try? actions.trackICloudStates("Dinner")[2], "in iCloud", "still in iCloud while downloading")
            songs.finish(synced.absent)
        }
        try actions.playTrack(3, inPlaylist: "Dinner")
        timer.invalidate()
        XCTAssertEqual(songs.started, [MacSongs.id(for: synced.absent)], "one download, the one the window would start")
        XCTAssertTrue(sawThePie)
        XCTAssertEqual(app.services.engine.currentURL, synced.absent, "the command returned only once it was playing")
        XCTAssertEqual(try actions.trackICloudStates("Dinner")[2], "in iCloud")
    }

    func testTheClickRouteAndTheScriptRouteStartTheSameDownloadForTheSameSong() throws {
        let synced = try openSynced()
        app.window(of: synced.doc).playRow(2)
        let byClick = (songs.started, cell(synced.doc, 2).cloudKind)
        songs.finish(synced.absent)
        app.tearDown()
        makeApp(root: cloud.url)
        try? FileManager.default.removeItem(at: cloud.url.appendingPathComponent("Dinner"))
        let again = try openSynced()
        var kindDuring: CloudIconState?
        let timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [self] _ in
            kindDuring = cell(again.doc, 2).cloudKind
            songs.finish(again.absent)
        }
        try actions.playTrack(3, inPlaylist: "Dinner")
        timer.invalidate()
        XCTAssertEqual(songs.started, byClick.0)
        XCTAssertEqual(kindDuring, byClick.1)
    }

    func testPlayingASongOnThisMacOrOutsideICloudByScriptPlaysAtOnceWithNoDownload() throws {
        let synced = try openSynced()
        try actions.playTrack(1, inPlaylist: "Dinner")
        XCTAssertEqual(app.services.engine.currentURL, synced.inside)
        try actions.playTrack(2, inPlaylist: "Dinner")
        XCTAssertEqual(app.services.engine.currentURL, synced.outside)
        XCTAssertEqual(songs.started, [], "no download")
        _ = expectFailure(ScriptError.noSuchTrack) { try actions.playTrack(0, inPlaylist: "Dinner") }
        _ = expectFailure(ScriptError.noSuchTrack) { try actions.playTrack(4, inPlaylist: "Dinner") }
        XCTAssertEqual(songs.started, [], "a bad position starts nothing")
    }

    func testAFailedDownloadByScriptReturnsANumberedErrorPlaysNothingAndTheWindowShowsTheFailure() throws {
        let synced = try openSynced()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [self] _ in songs.fail(synced.absent) }
        let failure = expectFailure(nil) { try actions.playTrack(3, inPlaylist: "Dinner") }     // the number is not decided; not asserted
        timer.invalidate()
        XCTAssertNotNil(failure)
        XCTAssertNil(app.services.engine.currentURL, "nothing plays")
        XCTAssertEqual(cell(synced.doc, 2).cloudKind, .exclamation, "the window shows the failed download, as a click would")
        XCTAssertEqual(try actions.trackICloudStates("Dinner")[2], "in iCloud", "location only")
    }
}
