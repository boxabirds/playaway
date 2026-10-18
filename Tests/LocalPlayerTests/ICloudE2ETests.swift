import XCTest
import AppKit
import CoreGraphics
@testable import LocalPlayer
@testable import PlayawayCore

/// End-to-end tests of the iCloud stories (18, 19, 20, 21, 22) against the built e2e bundle, driven from outside through
/// `open`, `osascript`, System Events and real mouse events. iCloud is the debug-only stand-in folder (`CloudStandIn`):
/// a temp folder is the Playaway folder, a placeholder is a song not on this Mac, the test "delivers" a download by
/// writing the file. Nothing touches the person's iCloud Drive or the app they use. The window tests need the screen
/// unlocked (System Events sees no windows of a locked session) and skip, not fail, when it is locked. They skip
/// unless the bundle exists: `scripts/run-e2e.sh` builds it.
///
/// Owner permission to run these was given on 2026-10-17 ("finish Mac iCloud you can run the tests").
@MainActor
final class ICloudE2ETests: XCTestCase {
    static let downloadSettle: TimeInterval = 1.5
    static let sheetTimeout: TimeInterval = 10
    static let playTimeout: TimeInterval = 15
    static let dragSteps = 12
    static let dragStepDelay: TimeInterval = 0.04
    static let dragSettle: TimeInterval = 1.0
    static let dragSourceSize: CGFloat = 160
    static let dragSourceInset: CGFloat = 40
    static let openPanelDelay: TimeInterval = 1.0
    static let listNames = { (urls: [String]) in urls.filter { !$0.hasPrefix(".") }.sorted() }

    let app = E2EApp()
    let dir = TempDir("icloude2e")
    var cloud: URL { dir.url.appendingPathComponent("Cloud", isDirectory: true) }
    var local: URL { dir.url.appendingPathComponent("Local", isDirectory: true) }
    private var readOnlyFolders: [URL] = []
    private var panelDiagnostics = ""

    override func setUpWithError() throws {
        try XCTSkipUnless(app.isBuilt, "dev bundle not built: run scripts/run-e2e.sh")
        continueAfterFailure = false
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        app.reset()
    }

    override func tearDown() {
        for folder in readOnlyFolders { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        app.tearDown()
    }

    // MARK: helpers

    func launch(unavailable: Bool = false) throws {
        try app.launch(environment: [CloudStandIn.environmentKey: unavailable ? CloudStandIn.unavailableValue : cloud.path])
    }

    /// System Events cannot see the windows of a locked session; the window tests skip rather than fail then.
    func needsScreen() throws {
        try XCTSkipIf(E2EApp.isScreenLocked, "the screen is locked: System Events sees no windows, so this window test cannot run now")
    }

    @discardableResult
    func localSong(_ fixture: String, as name: String? = nil) -> URL {
        let url = local.appendingPathComponent(name ?? fixture)
        try! FileManager.default.copyItem(at: Fixtures.url(fixture), to: url)
        return url
    }

    @discardableResult
    func cloudSong(_ fixture: String, in playlist: String, as name: String? = nil) -> URL {
        let folder = cloud.appendingPathComponent(playlist, isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name ?? fixture)
        try! FileManager.default.copyItem(at: Fixtures.url(fixture), to: url)
        return url
    }

    /// A song in iCloud but not on this Mac: only its placeholder is in the folder.
    @discardableResult
    func absentSong(_ name: String, in playlist: String) -> URL {
        let folder = cloud.appendingPathComponent(playlist, isDirectory: true)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try! Data().write(to: folder.appendingPathComponent(".\(name).icloud"))
        return folder.appendingPathComponent(name)
    }

    /// The download "arrives": the file is written whole and the placeholder goes, as iCloud does it.
    func deliver(_ fixture: String, to url: URL) {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".delivering-\(url.lastPathComponent)")
        try! FileManager.default.copyItem(at: Fixtures.url(fixture), to: temp)
        try! FileManager.default.moveItem(at: temp, to: url)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud"))
    }

    func failDownload(of url: URL) { try! Data().write(to: CloudStandIn.errorMarker(for: url)) }

    func names(in folder: URL) -> [String] { Self.listNames((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []) }

    func playlistFile(_ name: String, synced: Bool) -> URL {
        synced ? cloud.appendingPathComponent("\(name)/\(name).\(playlistFileExtension)") : local.appendingPathComponent("\(name).\(playlistFileExtension)")
    }

    /// A playlist made by script: unsynced in the local folder, or synced (its file inside the stand-in folder).
    func newPlaylist(_ name: String, synced: Bool, songs: [URL]) {
        if synced { try! FileManager.default.createDirectory(at: cloud.appendingPathComponent(name), withIntermediateDirectories: true) }
        XCTAssertEqual(app.osa("new playlist at \(E2EApp.quoted(playlistFile(name, synced: synced).path))").out, name)
        for song in songs {
            XCTAssertEqual(app.osa("add track \(E2EApp.quoted(song.path)) to \(E2EApp.quoted(name)) files \"add without syncing\"").status, 0, song.lastPathComponent)
        }
    }

    func syncValue(_ window: String) -> String { app.elements(identifier: ElementID.sync, inWindow: window).first?.value ?? "no sync button" }
    func scriptSync(_ name: String) -> String { app.osa("get iCloud sync of playlist document \(E2EApp.quoted(name))").out }
    func scriptStates(_ name: String) -> String { app.osa("get track iCloud states of playlist document \(E2EApp.quoted(name))").out }

    // MARK: 18.6 / 19.6 / 19.14: the cloud button, the Playlist and Files dialogs, the relaunch

    func testTheCloudButtonAsksMoveThenTheFilesQuestionCopiesTheSongsAndStaysOnAfterARelaunch() throws {   // 18 TC-07, TC-08, TC-16, TC-19, E2E-1; 19 TC-26, E2E-1; 19 TC-116
        try needsScreen()
        let one = localSong("track1.mp3"), two = localSong("track2.mp3")
        try launch()
        newPlaylist("Dinner", synced: false, songs: [one, two])
        XCTAssertEqual(syncValue("Dinner"), "off")
        XCTAssertEqual(app.cloudLabels(inWindow: "Dinner"), [], "no clouds on an unsynced playlist")
        XCTAssertTrue(app.click(identifier: ElementID.sync, inWindow: "Dinner"))
        let playlistSheet = try XCTUnwrap(app.waitForSheet(titled: PlaylistPrompt.title, onWindow: "Dinner"))
        XCTAssertEqual(playlistSheet.message, PlaylistPrompt.message)
        XCTAssertEqual(Set(playlistSheet.buttons), [PlaylistPrompt.moveLabel, PlaylistPrompt.dontSyncLabel])
        XCTAssertTrue(FileManager.default.fileExists(atPath: playlistFile("Dinner", synced: false).path), "nothing moved before the answer")
        XCTAssertTrue(app.clickSheetButton(PlaylistPrompt.moveLabel, onWindow: "Dinner"))
        let filesSheet = try XCTUnwrap(app.waitForSheet(titled: FilesPrompt.title, onWindow: "Dinner"))
        XCTAssertEqual(filesSheet.message, FilesPrompt.message)
        XCTAssertEqual(filesSheet.buttons, ["Copy to iCloud", "Move to iCloud", "Add Without Syncing"], "the owner's three buttons, Copy the default")
        XCTAssertTrue(FileManager.default.fileExists(atPath: one.path), "nothing copied before the answer")
        XCTAssertTrue(app.clickSheetButton("Copy to iCloud", onWindow: "Dinner"))
        XCTAssertTrue(app.waitForNoSheet(onWindow: "Dinner"))
        XCTAssertTrue(app.wait { self.names(in: self.cloud.appendingPathComponent("Dinner")) == ["Dinner.\(playlistFileExtension)", "track1.mp3", "track2.mp3"] },
                      "playlist and songs in the Playaway folder: \(names(in: cloud.appendingPathComponent("Dinner")))")
        XCTAssertTrue(FileManager.default.fileExists(atPath: one.path) && FileManager.default.fileExists(atPath: two.path), "copied, the originals stay")
        XCTAssertFalse(FileManager.default.fileExists(atPath: playlistFile("Dinner", synced: false).path), "the playlist file moved")
        XCTAssertEqual(syncValue("Dinner"), "on")
        XCTAssertEqual(app.cloudLabels(inWindow: "Dinner"), ["In iCloud", "In iCloud"])
        XCTAssertEqual(app.rowLabels(inWindow: "Dinner"), ["track1, in iCloud", "track2, in iCloud"])
        XCTAssertEqual(scriptSync("Dinner"), "true")
        XCTAssertEqual(app.osa("play track 2 in \"Dinner\"").status, 0)
        XCTAssertTrue(app.waitFor("get current track", equals: "track2.mp3"), "plays from its new place")
        // After a relaunch the playlist opens from its place in the Playaway folder, still on.
        app.quit()
        try launch()
        app.open(playlistFile("Dinner", synced: true))
        XCTAssertTrue(app.wait { self.app.osa("get name of every playlist document").out.contains("Dinner") })
        XCTAssertEqual(scriptSync("Dinner"), "true")
        XCTAssertEqual(syncValue("Dinner"), "on")
        XCTAssertEqual(app.cloudLabels(inWindow: "Dinner"), ["In iCloud", "In iCloud"])
    }

    func testDontSyncLeavesThePlaylistWhereItIsWithNoClouds() throws {                                       // 18 TC-08, E2E-1
        try needsScreen()
        let one = localSong("track1.mp3")
        try launch()
        newPlaylist("Lunch", synced: false, songs: [one])
        XCTAssertTrue(app.click(identifier: ElementID.sync, inWindow: "Lunch"))
        XCTAssertNotNil(app.waitForSheet(titled: PlaylistPrompt.title, onWindow: "Lunch"))
        XCTAssertTrue(app.clickSheetButton(PlaylistPrompt.dontSyncLabel, onWindow: "Lunch"))
        XCTAssertTrue(app.waitForNoSheet(onWindow: "Lunch"))
        Thread.sleep(forTimeInterval: Self.downloadSettle)
        XCTAssertTrue(FileManager.default.fileExists(atPath: playlistFile("Lunch", synced: false).path))
        XCTAssertEqual(names(in: cloud), [], "nothing in the Playaway folder")
        XCTAssertEqual(syncValue("Lunch"), "off")
        XCTAssertEqual(app.cloudLabels(inWindow: "Lunch"), [])
        XCTAssertEqual(scriptSync("Lunch"), "false")
        XCTAssertEqual(app.osa("play track 1 in \"Lunch\"").status, 0, "still plays from where it is")
    }

    func testMoveToICloudMovesTheSongsAndReportsTheOneThatCouldOnlyBeCopied() throws {                       // 19 E2E-2, TC-26 (report box)
        try needsScreen()
        let one = localSong("track1.mp3")
        let readOnly = local.appendingPathComponent("ReadOnly", isDirectory: true)
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        let locked = readOnly.appendingPathComponent("track2.mp3")
        try FileManager.default.copyItem(at: Fixtures.url("track2.mp3"), to: locked)
        try launch()
        newPlaylist("Brunch", synced: false, songs: [one, locked])
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)   // its folder cannot lose a file
        readOnlyFolders.append(readOnly)
        XCTAssertTrue(app.click(identifier: ElementID.sync, inWindow: "Brunch"))
        XCTAssertNotNil(app.waitForSheet(titled: PlaylistPrompt.title, onWindow: "Brunch"))
        XCTAssertTrue(app.clickSheetButton(PlaylistPrompt.moveLabel, onWindow: "Brunch"))
        XCTAssertNotNil(app.waitForSheet(titled: FilesPrompt.title, onWindow: "Brunch"))
        XCTAssertTrue(app.clickSheetButton("Move to iCloud", onWindow: "Brunch"))
        let report = try XCTUnwrap(app.waitForSheet(titled: FilesPrompt.copiedInsteadReport(1)!, onWindow: "Brunch"), "the report box names the one copied instead")
        XCTAssertEqual(report.buttons, ["OK"])
        XCTAssertTrue(app.clickSheetButton("OK", onWindow: "Brunch"))
        XCTAssertTrue(app.waitForNoSheet(onWindow: "Brunch"))
        XCTAssertEqual(names(in: cloud.appendingPathComponent("Brunch")), ["Brunch.\(playlistFileExtension)", "track1.mp3", "track2.mp3"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: one.path), "moved")
        XCTAssertTrue(FileManager.default.fileExists(atPath: locked.path), "copied instead: the original stays")
        XCTAssertEqual(app.cloudLabels(inWindow: "Brunch"), ["In iCloud", "In iCloud"])
        XCTAssertEqual(app.osa("play track 1 in \"Brunch\"").status, 0)
        XCTAssertTrue(app.waitFor("get current track", equals: "track1.mp3"), "plays from the Playaway folder")
    }

    // MARK: 19.10 / 20.9: Add Without Syncing

    func testAddWithoutSyncingLeavesTheSongsWhereTheyAreWithCrossedOutCloudsAndOnlyAMissingFileDims() throws {   // 19 TC-75, E2E-4; 20 E2E-4
        try needsScreen()
        let one = localSong("track1.mp3"), two = localSong("track2.mp3")
        try launch()
        newPlaylist("Supper", synced: false, songs: [one, two])
        XCTAssertTrue(app.click(identifier: ElementID.sync, inWindow: "Supper"))
        XCTAssertNotNil(app.waitForSheet(titled: PlaylistPrompt.title, onWindow: "Supper"))
        XCTAssertTrue(app.clickSheetButton(PlaylistPrompt.moveLabel, onWindow: "Supper"))
        XCTAssertNotNil(app.waitForSheet(titled: FilesPrompt.title, onWindow: "Supper"))
        XCTAssertTrue(app.clickSheetButton("Add Without Syncing", onWindow: "Supper"))
        XCTAssertTrue(app.waitForNoSheet(onWindow: "Supper"))
        XCTAssertTrue(app.wait { self.syncValue("Supper") == "on" }, "sync stays on")
        XCTAssertEqual(names(in: cloud.appendingPathComponent("Supper")), ["Supper.\(playlistFileExtension)"], "only the playlist moved")
        XCTAssertTrue(FileManager.default.fileExists(atPath: one.path) && FileManager.default.fileExists(atPath: two.path))
        XCTAssertTrue(app.wait { self.app.cloudLabels(inWindow: "Supper") == ["Not in iCloud", "Not in iCloud"] }, "the rows follow: \(app.cloudLabels(inWindow: "Supper"))")
        XCTAssertEqual(app.rowLabels(inWindow: "Supper"), ["track1, not in iCloud", "track2, not in iCloud"], "normal rows: nothing says not on this Mac")
        XCTAssertEqual(scriptStates("Supper"), "not in iCloud, not in iCloud")
        XCTAssertEqual(app.osa("play track 1 in \"Supper\"").status, 0)
        XCTAssertTrue(app.waitFor("get current track", equals: "track1.mp3"))
        // A file that is gone dims its row (after a play is attempted), the local one beside it does not.
        try FileManager.default.removeItem(at: two)
        XCTAssertEqual(app.osaError("play track 2 in \"Supper\"")?.number, 1004)
        // The row says it could not be played (the hazard) once a play was attempted, and carries no cloud (a file that
        // cannot be found has no place to report); the row beside it is untouched.
        XCTAssertTrue(app.wait { self.app.rowLabels(inWindow: "Supper").last?.contains("could not be played") == true }, "\(app.rowLabels(inWindow: "Supper"))")
        XCTAssertEqual(app.rowLabels(inWindow: "Supper"), ["track1, playing, not in iCloud", "track2, could not be played"])
        XCTAssertEqual(app.cloudLabels(inWindow: "Supper"), ["Not in iCloud"], "the local song keeps its crossed-out cloud")
    }

    // MARK: 20.5 / 20.18 / 22.17: the row clouds and a download on play

    func testRowsShowLocationAndAvailabilityAndASongNotOnThisMacDownloadsWhenPlayed() throws {               // 20 TC-17, TC-18, TC-19, E2E-1, E2E-2, E2E-5 (stand-in); 22 E2E-6
        try needsScreen()
        cloudSong("long180.mp3", in: "Trip")
        let outside = localSong("track2.mp3")
        let absent = absentSong("track3.mp3", in: "Trip")
        try launch()
        newPlaylist("Trip", synced: true, songs: [cloud.appendingPathComponent("Trip/long180.mp3"), outside])
        // The absent song cannot be added by script (it has no file here); the playlist file gains it directly.
        app.quit()
        let file = playlistFile("Trip", synced: true)
        guard case .loaded(var playlist) = PlaylistStore().load(from: file) else { return XCTFail("playlist unreadable") }
        playlist.tracks.append(Track(id: UUID(), reference: TrackReference(bookmark: Data(), lastKnownPath: absent.path, fileName: absent.lastPathComponent)))
        XCTAssertEqual(PlaylistStore().save(playlist, to: file), .saved)
        try launch()
        app.open(file)
        XCTAssertTrue(app.wait { self.app.osa("get name of every playlist document").out.contains("Trip") })
        XCTAssertEqual(app.cloudLabels(inWindow: "Trip"), ["In iCloud", "Not in iCloud", "In iCloud, not on this Mac"])
        XCTAssertEqual(app.rowLabels(inWindow: "Trip"), ["long180, playing, in iCloud", "track2, not in iCloud", "track3, not on this Mac"], "the opened playlist plays its first song")
        XCTAssertEqual(scriptStates("Trip"), "in iCloud, not in iCloud, in iCloud", "location only by script")
        // The icons sit at the right-hand end of their rows and are drawn (at half strength) in the current appearance.
        let icons = app.elements(identifier: ElementID.songCloud, inWindow: "Trip")
        let table = try XCTUnwrap(app.elements(identifier: ElementID.tracks, inWindow: "Trip").first)
        for icon in icons {
            XCTAssertGreaterThan(icon.position.x, table.position.x + table.size.width / 2, "trailing: \(icon)")
            XCTAssertGreaterThan(app.distinctPixels(in: CGRect(origin: icon.position, size: icon.size), into: dir), 0, "something is drawn for \(icon.description)")
        }
        // Playing the absent song by script starts the same download the window would: the pie shows, nothing plays yet,
        // the script returns once the song plays after the file arrives.
        let play = app.osaInBackground("play track 3 in \"Trip\"")
        XCTAssertTrue(app.wait { self.app.cloudLabels(inWindow: "Trip").last == "Downloading, click to cancel" })
        XCTAssertEqual(app.rowLabels(inWindow: "Trip").last, "track3, downloading from iCloud")
        XCTAssertEqual(app.rowLabels(inWindow: "Trip").first, "long180, playing, in iCloud", "the first song plays on until the file is here")
        XCTAssertTrue(play.isRunning, "the script waits; the app answers no other script meanwhile")
        deliver("track3.mp3", to: absent)
        play.waitUntilExit()
        XCTAssertEqual(play.terminationStatus, 0, "the script returned once the song played")
        XCTAssertTrue(app.waitFor("get current track", equals: "track3.mp3", timeout: Self.playTimeout))
        XCTAssertEqual(app.cloudLabels(inWindow: "Trip").last, "In iCloud")
        XCTAssertEqual(app.rowLabels(inWindow: "Trip").last, "track3, playing, in iCloud")
    }

    // MARK: 20.22: real clicks on the four icons

    func testClicksOnTheRowCloudsFollowTheSharedRuleAndNeverPlayTheRow() throws {                            // 20 E2E-6; 31 tap rule
        try needsScreen()
        cloudSong("long180.mp3", in: "Clicks")
        let outside = localSong("track2.mp3")
        let absent = absentSong("track3.mp3", in: "Clicks")
        try launch()
        newPlaylist("Clicks", synced: true, songs: [cloud.appendingPathComponent("Clicks/long180.mp3"), outside])
        app.quit()
        let file = playlistFile("Clicks", synced: true)
        guard case .loaded(var playlist) = PlaylistStore().load(from: file) else { return XCTFail("playlist unreadable") }
        playlist.tracks.append(Track(id: UUID(), reference: TrackReference(bookmark: Data(), lastKnownPath: absent.path, fileName: absent.lastPathComponent)))
        XCTAssertEqual(PlaylistStore().save(playlist, to: file), .saved)
        try launch()
        app.open(file)
        XCTAssertTrue(app.wait { self.app.cloudLabels(inWindow: "Clicks").count == 3 })
        // Crossed-out: the Files question for that song; Add Without Syncing leaves it crossed-out, nothing plays.
        XCTAssertTrue(app.click(identifier: ElementID.songCloud, inWindow: "Clicks", index: 2))
        XCTAssertNotNil(app.waitForSheet(titled: FilesPrompt.title, onWindow: "Clicks"))
        XCTAssertTrue(app.clickSheetButton("Add Without Syncing", onWindow: "Clicks"))
        XCTAssertTrue(app.waitForNoSheet(onWindow: "Clicks"))
        XCTAssertEqual(app.cloudLabels(inWindow: "Clicks")[1], "Not in iCloud")
        XCTAssertEqual(app.osa("get current track").out, "long180.mp3", "the click never plays the row")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        // Outline: nothing.
        XCTAssertTrue(app.click(identifier: ElementID.songCloud, inWindow: "Clicks", index: 1))
        Thread.sleep(forTimeInterval: Self.downloadSettle)
        XCTAssertNil(app.sheet(onWindow: "Clicks"))
        XCTAssertEqual(app.osa("get current track").out, "long180.mp3")
        XCTAssertEqual(app.cloudLabels(inWindow: "Clicks")[0], "In iCloud")
        // The pie: a click cancels the download; the row is the outline cloud, still not on this Mac, nothing plays.
        var play = app.osaInBackground("play track 3 in \"Clicks\"")
        XCTAssertTrue(app.wait { self.app.cloudLabels(inWindow: "Clicks")[2] == "Downloading, click to cancel" })
        XCTAssertTrue(app.click(identifier: ElementID.songCloud, inWindow: "Clicks", index: 3))
        XCTAssertTrue(app.wait { self.app.cloudLabels(inWindow: "Clicks")[2] == "In iCloud, not on this Mac" })
        play.waitUntilExit()
        XCTAssertNotEqual(play.terminationStatus, 0, "the scripted play ends without the song: cancelled")
        XCTAssertEqual(app.osa("get current track").out, "long180.mp3")
        // A failed download: the exclamation mark; a click on it restarts the download and the pie shows again.
        failDownload(of: absent)
        play = app.osaInBackground("play track 3 in \"Clicks\"")
        XCTAssertTrue(app.wait { self.app.cloudLabels(inWindow: "Clicks")[2] == DownloadState.failedAccessibilityLabel })
        play.waitUntilExit()
        XCTAssertEqual(app.rowLabels(inWindow: "Clicks")[2], "track3, \(DownloadState.failedAccessibilityLabel)")
        try FileManager.default.removeItem(at: CloudStandIn.errorMarker(for: absent))
        XCTAssertTrue(app.click(identifier: ElementID.songCloud, inWindow: "Clicks", index: 3))
        XCTAssertTrue(app.wait { self.app.cloudLabels(inWindow: "Clicks")[2] == "Downloading, click to cancel" })
        deliver("track3.mp3", to: absent)
        XCTAssertTrue(app.wait { self.app.cloudLabels(inWindow: "Clicks")[2] == "In iCloud" })
        XCTAssertTrue(app.waitFor("get current track", equals: "track3.mp3", timeout: Self.playTimeout), "the retried download plays the song that was asked for")
    }

    // MARK: 18.14 / 22.13: iCloud unavailable

    func testUnavailableICloudShowsADisabledCloudWithTheReasonAndScriptsGetTheSameReason() throws {           // 18 TC-33, E2E-3; 22 E2E-5
        try needsScreen()
        let one = localSong("track1.mp3")
        try launch(unavailable: true)
        newPlaylist("Offline", synced: false, songs: [one])
        let button = try XCTUnwrap(app.elements(identifier: ElementID.sync, inWindow: "Offline").first)
        XCTAssertEqual(button.value, "off, \(ICloudAvailability.unavailableReason)", "VoiceOver reads the state and the reason")
        let reason = try XCTUnwrap(app.elements(identifier: ElementID.syncReason, inWindow: "Offline").first)
        XCTAssertEqual(reason.value, ICloudAvailability.unavailableReason)
        XCTAssertTrue(app.click(identifier: ElementID.sync, inWindow: "Offline"))
        Thread.sleep(forTimeInterval: Self.downloadSettle)
        XCTAssertNil(app.sheet(onWindow: "Offline"), "a disabled switch asks nothing")
        let refused = try XCTUnwrap(app.osaError("sync playlist \"Offline\" answering \"move\""))
        XCTAssertEqual(refused.number, 1009)
        XCTAssertTrue(refused.message.contains(ICloudAvailability.unavailableReason), refused.message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: playlistFile("Offline", synced: false).path), "nothing moved")
        XCTAssertEqual(names(in: cloud), [])
        XCTAssertEqual(scriptSync("Offline"), "false", "reads still work")
        XCTAssertEqual(scriptStates("Offline"), "not in iCloud")
        XCTAssertEqual(app.osaError("add track \(E2EApp.quoted(one.path)) to \"Offline\" files \"copy to iCloud\"")?.number, 1009)
    }

    // MARK: 22.9: script route and the dictionary (no window needed)

    func testScriptTurnsSyncOnWithAnswersReturnsTheReportAndReadsTheStates() throws {                        // 22 E2E-1, TC-01, TC-03, TC-05, TC-09
        let one = localSong("track1.mp3"), two = localSong("track2.mp3"), three = localSong("track3.mp3")
        try launch()
        newPlaylist("Script", synced: false, songs: [one, two])
        XCTAssertEqual(scriptSync("Script"), "false")
        XCTAssertEqual(scriptStates("Script"), "not in iCloud, not in iCloud")
        let report = app.osa("sync playlist \"Script\" answering \"move\" files \"copy to iCloud\"")
        XCTAssertEqual(report.status, 0, report.err)
        for part in ["moved:0", "copied:2", "copied instead:0", "failed:0", "path:\(playlistFile("Script", synced: true).canonicalPath)"] {
            XCTAssertTrue(report.out.contains(part), "\(part) in \(report.out)")
        }
        XCTAssertEqual(scriptSync("Script"), "true")
        XCTAssertEqual(scriptStates("Script"), "in iCloud, in iCloud")
        XCTAssertEqual(names(in: cloud.appendingPathComponent("Script")), ["Script.\(playlistFileExtension)", "track1.mp3", "track2.mp3"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: one.path), "copied: the original stays")
        // A scripted add into the synced playlist takes the Files answer; without one the song is added without syncing.
        XCTAssertEqual(app.osa("add track \(E2EApp.quoted(three.path)) to \"Script\" files \"copy to iCloud\"").status, 0)
        XCTAssertEqual(scriptStates("Script"), "in iCloud, in iCloud, in iCloud")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cloud.appendingPathComponent("Script/track3.mp3").path))
        let four = localSong("long30.mp3")
        XCTAssertEqual(app.osa("add track \(E2EApp.quoted(four.path)) to \"Script\"").status, 0)
        XCTAssertEqual(scriptStates("Script"), "in iCloud, in iCloud, in iCloud, not in iCloud")
        XCTAssertEqual(names(in: cloud.appendingPathComponent("Script")), ["Script.\(playlistFileExtension)", "track1.mp3", "track2.mp3", "track3.mp3"])
        // Syncing an already synced playlist changes nothing and reports nothing done.
        let again = app.osa("sync playlist \"Script\" answering \"move\" files \"move to iCloud\"")
        XCTAssertEqual(again.status, 0, again.err)
        XCTAssertTrue(again.out.contains("moved:0") && again.out.contains("copied:0"), again.out)
        XCTAssertEqual(app.osa("play track 3 in \"Script\"").status, 0)
        XCTAssertTrue(app.waitFor("get current track", equals: "track3.mp3"))
    }

    func testTheDictionaryListsTheICloudEntriesAndNoTurnOffOrDelete() throws {                               // 22 E2E-3
        let result = app.sh("/usr/bin/sdef", [app.appURL.path])
        XCTAssertEqual(result.status, 0, result.err)
        for name in ["sync playlist", "iCloud sync", "track iCloud states", "sync report", "files", "answering"] {
            XCTAssertTrue(result.out.contains("name=\"\(name)\""), name)
        }
        XCTAssertFalse(result.out.lowercased().contains("delete"))
        XCTAssertFalse(result.out.lowercased().contains("turn off"))
        XCTAssertFalse(result.out.lowercased().contains("unsync"))
    }

    func testScriptPlayOfASongNotOnThisMacWaitsForTheDownloadAndErrorsWhenItFails() throws {                  // 22 E2E-6 (script side), TC-80
        cloudSong("long180.mp3", in: "Wait")
        let absent = absentSong("track3.mp3", in: "Wait")
        let failing = absentSong("track2.mp3", in: "Wait")
        try launch()
        newPlaylist("Wait", synced: true, songs: [cloud.appendingPathComponent("Wait/long180.mp3")])
        app.quit()
        let file = playlistFile("Wait", synced: true)
        guard case .loaded(var playlist) = PlaylistStore().load(from: file) else { return XCTFail("playlist unreadable") }
        for url in [absent, failing] {
            playlist.tracks.append(Track(id: UUID(), reference: TrackReference(bookmark: Data(), lastKnownPath: url.path, fileName: url.lastPathComponent)))
        }
        XCTAssertEqual(PlaylistStore().save(playlist, to: file), .saved)
        try launch()
        app.open(file)
        XCTAssertTrue(app.wait { self.scriptStates("Wait") == "in iCloud, in iCloud, in iCloud" })
        let play = app.osaInBackground("play track 2 in \"Wait\"")
        Thread.sleep(forTimeInterval: Self.downloadSettle)
        XCTAssertTrue(play.isRunning, "waits for the download (and answers no other script meanwhile)")
        deliver("track3.mp3", to: absent)
        play.waitUntilExit()
        XCTAssertEqual(play.terminationStatus, 0)
        XCTAssertEqual(app.osa("get current track").out, "track3.mp3")
        XCTAssertEqual(app.osa("get playing").out, "true")
        failDownload(of: failing)
        let failed = try XCTUnwrap(app.osaError("play track 3 in \"Wait\"", timeout: Self.playTimeout))
        XCTAssertEqual(failed.number, 1011)
        XCTAssertTrue(failed.message.contains("track2.mp3"), failed.message)
        XCTAssertEqual(app.osa("get current track").out, "track3.mp3", "the music carries on")
    }

    // MARK: 22.9 E2E-2: the window route and the script route give the same files and states

    func testTurningSyncOnByWindowAndByScriptGiveTheSameFilesRowsAndStates() throws {
        try needsScreen()
        let a1 = localSong("track1.mp3", as: "a1.mp3"), a2 = localSong("track2.mp3", as: "a2.mp3")
        let b1 = localSong("track1.mp3", as: "b1.mp3"), b2 = localSong("track2.mp3", as: "b2.mp3")
        try launch()
        newPlaylist("ByWindow", synced: false, songs: [a1, a2])
        newPlaylist("ByScript", synced: false, songs: [b1, b2])
        XCTAssertTrue(app.click(identifier: ElementID.sync, inWindow: "ByWindow"))
        XCTAssertNotNil(app.waitForSheet(titled: PlaylistPrompt.title, onWindow: "ByWindow"))
        XCTAssertTrue(app.clickSheetButton(PlaylistPrompt.moveLabel, onWindow: "ByWindow"))
        XCTAssertNotNil(app.waitForSheet(titled: FilesPrompt.title, onWindow: "ByWindow"))
        XCTAssertTrue(app.clickSheetButton("Copy to iCloud", onWindow: "ByWindow"))
        XCTAssertTrue(app.waitForNoSheet(onWindow: "ByWindow"))
        XCTAssertEqual(app.osa("sync playlist \"ByScript\" answering \"move\" files \"copy to iCloud\"").status, 0)
        let byWindow = names(in: cloud.appendingPathComponent("ByWindow")).map { $0.replacingOccurrences(of: "a", with: "") }
        let byScript = names(in: cloud.appendingPathComponent("ByScript")).map { $0.replacingOccurrences(of: "b", with: "") }
        XCTAssertEqual(byWindow, ["ByWindow.\(playlistFileExtension)".replacingOccurrences(of: "a", with: ""), "1.mp3", "2.mp3"])
        XCTAssertEqual(byWindow.dropFirst(), byScript.dropFirst(), "the same files in the Playaway folder")
        XCTAssertEqual(scriptSync("ByWindow"), scriptSync("ByScript"))
        XCTAssertEqual(scriptStates("ByWindow"), scriptStates("ByScript"))
        XCTAssertEqual(app.cloudLabels(inWindow: "ByWindow"), app.cloudLabels(inWindow: "ByScript"))
        XCTAssertEqual(syncValue("ByWindow"), syncValue("ByScript"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a1.path) && FileManager.default.fileExists(atPath: b1.path), "both copied")
    }

    // MARK: 21.4 / 21.9 / 21.13: real drags

    func testADragIntoASyncedPlaylistAsksTheFilesQuestionOnceAndCopiesAndIntoAnUnsyncedOneAsksNothing() throws {   // 21 TC-11, E2E-1, E2E-2
        try needsScreen()
        cloudSong("track1.mp3", in: "Drop")
        let one = localSong("track2.mp3"), two = localSong("track3.mp3")
        try launch()
        newPlaylist("Drop", synced: true, songs: [cloud.appendingPathComponent("Drop/track1.mp3")])
        try drag([one, two], intoWindow: "Drop")
        let sheet = try XCTUnwrap(app.waitForSheet(titled: FilesPrompt.title, onWindow: "Drop"), "one question for the drop")
        XCTAssertEqual(sheet.buttons, ["Copy to iCloud", "Move to iCloud", "Add Without Syncing"])
        XCTAssertEqual(names(in: cloud.appendingPathComponent("Drop")), ["Drop.\(playlistFileExtension)", "track1.mp3"], "nothing copied before the answer")
        XCTAssertTrue(app.clickSheetButton("Copy to iCloud", onWindow: "Drop"))
        XCTAssertTrue(app.waitForNoSheet(onWindow: "Drop"))
        XCTAssertTrue(app.wait { self.app.cloudLabels(inWindow: "Drop") == ["In iCloud", "In iCloud", "In iCloud"] }, "\(app.cloudLabels(inWindow: "Drop"))")
        XCTAssertEqual(names(in: cloud.appendingPathComponent("Drop")), ["Drop.\(playlistFileExtension)", "track1.mp3", "track2.mp3", "track3.mp3"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: one.path), "copied, the originals stay")
        XCTAssertEqual(scriptStates("Drop"), "in iCloud, in iCloud, in iCloud")
        XCTAssertNil(app.sheet(onWindow: "Drop"), "asked once")
        // An unsynced playlist takes a drop as it always did: rows added, no question, no clouds.
        let three = localSong("long30.mp3")
        newPlaylist("Plain", synced: false, songs: [])
        try drag([three], intoWindow: "Plain")
        XCTAssertTrue(app.wait { self.app.osa("get track count of playlist document \"Plain\"").out == "1" })
        Thread.sleep(forTimeInterval: Self.dragSettle)
        XCTAssertNil(app.sheet(onWindow: "Plain"))
        XCTAssertEqual(app.cloudLabels(inWindow: "Plain"), [])
        XCTAssertEqual(names(in: cloud), ["Drop"], "nothing of the unsynced playlist in the Playaway folder")
    }

    func testADragWithAddWithoutSyncingAddsPlayableRowsWithCrossedOutClouds() throws {                        // 21 TC-85, E2E-4
        try needsScreen()
        cloudSong("track1.mp3", in: "Keep")
        let one = localSong("track2.mp3"), two = localSong("track3.mp3")
        try launch()
        newPlaylist("Keep", synced: true, songs: [cloud.appendingPathComponent("Keep/track1.mp3")])
        try drag([one, two], intoWindow: "Keep")
        XCTAssertNotNil(app.waitForSheet(titled: FilesPrompt.title, onWindow: "Keep"))
        XCTAssertTrue(app.clickSheetButton("Add Without Syncing", onWindow: "Keep"))
        XCTAssertTrue(app.waitForNoSheet(onWindow: "Keep"))
        XCTAssertTrue(app.wait { self.app.cloudLabels(inWindow: "Keep") == ["In iCloud", "Not in iCloud", "Not in iCloud"] }, "\(app.cloudLabels(inWindow: "Keep"))")
        XCTAssertEqual(app.rowLabels(inWindow: "Keep"), ["track1, in iCloud", "track2, not in iCloud", "track3, not in iCloud"], "normal brightness: nothing says not on this Mac")
        XCTAssertEqual(names(in: cloud.appendingPathComponent("Keep")), ["Keep.\(playlistFileExtension)", "track1.mp3"], "nothing moved or copied")
        XCTAssertTrue(FileManager.default.fileExists(atPath: one.path) && FileManager.default.fileExists(atPath: two.path))
        XCTAssertEqual(app.osa("play track 2 in \"Keep\"").status, 0)
        XCTAssertTrue(app.waitFor("get current track", equals: "track2.mp3"), "plays from where it is")
        XCTAssertEqual(syncValue("Keep"), "on")
    }

    func testADragAndAddFilesByMenuGiveTheSameDialogFilesAndRows() throws {                                 // 21 E2E-5
        try needsScreen()
        cloudSong("track1.mp3", in: "Dragged"); cloudSong("track1.mp3", in: "Chosen")
        let dragFolder = local.appendingPathComponent("ForDrag", isDirectory: true), menuFolder = local.appendingPathComponent("ForMenu", isDirectory: true)
        for folder in [dragFolder, menuFolder] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in ["track2.mp3", "track3.mp3"] { try FileManager.default.copyItem(at: Fixtures.url(name), to: folder.appendingPathComponent(name)) }
        }
        try launch()
        newPlaylist("Dragged", synced: true, songs: [cloud.appendingPathComponent("Dragged/track1.mp3")])
        newPlaylist("Chosen", synced: true, songs: [cloud.appendingPathComponent("Chosen/track1.mp3")])
        try drag([dragFolder.appendingPathComponent("track2.mp3"), dragFolder.appendingPathComponent("track3.mp3")], intoWindow: "Dragged")
        let dragSheet = try XCTUnwrap(app.waitForSheet(titled: FilesPrompt.title, onWindow: "Dragged"))
        XCTAssertTrue(app.clickSheetButton("Copy to iCloud", onWindow: "Dragged"))
        XCTAssertTrue(app.waitForNoSheet(onWindow: "Dragged"))
        try addFilesByMenu(in: menuFolder, toWindow: "Chosen")
        let menuSheetFound = app.waitForSheet(titled: FilesPrompt.title, onWindow: "Chosen")
        XCTAssertNotNil(menuSheetFound, "the same question after Add Files; panel steps: \(panelDiagnostics)")
        let menuSheet = try XCTUnwrap(menuSheetFound)
        XCTAssertEqual(menuSheet.title, dragSheet.title)
        XCTAssertEqual(menuSheet.message, dragSheet.message)
        XCTAssertEqual(menuSheet.buttons, dragSheet.buttons)
        XCTAssertTrue(app.clickSheetButton("Copy to iCloud", onWindow: "Chosen"))
        XCTAssertTrue(app.waitForNoSheet(onWindow: "Chosen"))
        XCTAssertTrue(app.wait { self.app.cloudLabels(inWindow: "Chosen").count == 3 && self.app.cloudLabels(inWindow: "Dragged").count == 3 })
        XCTAssertEqual(names(in: cloud.appendingPathComponent("Dragged")).dropFirst(), names(in: cloud.appendingPathComponent("Chosen")).dropFirst(), "the same files")
        XCTAssertEqual(names(in: cloud.appendingPathComponent("Chosen")), ["Chosen.\(playlistFileExtension)", "track1.mp3", "track2.mp3", "track3.mp3"])
        XCTAssertEqual(app.cloudLabels(inWindow: "Dragged"), app.cloudLabels(inWindow: "Chosen"))
        XCTAssertEqual(app.rowLabels(inWindow: "Dragged"), app.rowLabels(inWindow: "Chosen"))
        XCTAssertEqual(scriptStates("Dragged"), scriptStates("Chosen"))
    }

    // MARK: driving a real drag and the Add Files panel

    /// Drags the files from a small window of this process onto the song list of the app's window with real mouse
    /// events, as a person would from Finder. The events are posted from another thread while this one pumps events,
    /// because the drag's own tracking loop runs inside the mouse-down.
    func drag(_ urls: [URL], intoWindow window: String) throws {
        _ = app.ax("set frontmost to true")
        _ = app.ax("perform action \"AXRaise\" of window \(E2EApp.quoted(window))")     // the drop lands on the window in front
        Thread.sleep(forTimeInterval: Self.dragSettle)
        let table = try XCTUnwrap(app.elements(identifier: ElementID.tracks, inWindow: window).first, "the song list of \(window)")
        let target = CGPoint(x: table.position.x + table.size.width / 2, y: table.position.y + table.size.height * 0.8)
        let source = DragSourceWindow(urls: urls)
        let from = source.centerInScreenCoordinates
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            func post(_ type: CGEventType, at point: CGPoint) {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            }
            post(.mouseMoved, at: from)
            Thread.sleep(forTimeInterval: Self.dragStepDelay)
            post(.leftMouseDown, at: from)
            Thread.sleep(forTimeInterval: Self.dragStepDelay * 4)
            for step in 1...Self.dragSteps {
                let t = CGFloat(step) / CGFloat(Self.dragSteps)
                post(.leftMouseDragged, at: CGPoint(x: from.x + (target.x - from.x) * t, y: from.y + (target.y - from.y) * t))
                Thread.sleep(forTimeInterval: Self.dragStepDelay)
            }
            Thread.sleep(forTimeInterval: Self.dragStepDelay * 4)
            post(.leftMouseUp, at: target)
            done.signal()
        }
        let deadline = Date().addingTimeInterval(10)
        while done.wait(timeout: .now()) == .timedOut && Date() < deadline { source.pumpEvents(for: 0.02) }
        source.pumpEvents(for: Self.dragSettle)
        source.close()
    }

    /// File > Add Files…, then the open panel (its own window, "Open"): Go to Folder, the folder's path, select all,
    /// Open. Each step's windows and the panel's elements are kept for the failure message.
    func addFilesByMenu(in folder: URL, toWindow window: String) throws {
        _ = app.ax("set frontmost to true")
        _ = app.ax("perform action \"AXRaise\" of window \(E2EApp.quoted(window))")
        Thread.sleep(forTimeInterval: Self.dragSettle)
        XCTAssertEqual(app.ax("click menu item \"Add Files…\" of menu 1 of menu bar item \"File\" of menu bar 1").status, 0)
        XCTAssertTrue(app.wait { self.app.ax("exists window \"Open\"").out == "true" }, "the open panel; windows now: \(app.ax("get name of every window").out)")
        Thread.sleep(forTimeInterval: Self.openPanelDelay)
        let shot = { (name: String) in
            self.panelDiagnostics += " [\(name): windows=\(self.app.ax("get name of every window").out); sheets of Open=\(self.app.ax("get count of sheets of window \"Open\"").out)]"
        }
        shot("opened")
        XCTAssertEqual(app.ax("keystroke \"g\" using {command down, shift down}").status, 0)
        Thread.sleep(forTimeInterval: Self.openPanelDelay)
        shot("goto")
        XCTAssertEqual(app.ax("keystroke \(E2EApp.quoted(folder.path))").status, 0)
        Thread.sleep(forTimeInterval: Self.openPanelDelay)
        XCTAssertEqual(app.ax("keystroke return").status, 0)
        Thread.sleep(forTimeInterval: Self.openPanelDelay)
        shot("went")
        XCTAssertEqual(app.ax("keystroke \"a\" using command down").status, 0)
        Thread.sleep(forTimeInterval: Self.openPanelDelay)
        shot("selected")
        // Return opens the selected files (the panel's Open button is not a plain child of its window).
        XCTAssertEqual(app.ax("keystroke return").status, 0)
        XCTAssertTrue(app.wait { self.app.ax("exists window \"Open\"").out == "false" }, "the panel closes; \(panelDiagnostics); buttons: \(app.ax("get name of every button of window \"Open\"").out)")
        shot("after")
    }
}

/// A small floating window of the test process that starts a file drag on mouse-down.
@MainActor
final class DragSourceWindow {
    private let window: NSWindow
    private let view: DragSourceView

    init(urls: [URL]) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let screen = NSScreen.main!.frame
        let size = ICloudE2ETests.dragSourceSize
        let frame = NSRect(x: screen.minX + ICloudE2ETests.dragSourceInset, y: screen.maxY - ICloudE2ETests.dragSourceInset - size, width: size, height: size)
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .floating
        window.backgroundColor = .systemOrange
        window.isReleasedWhenClosed = false
        view = DragSourceView(urls: urls)
        window.contentView = view
        window.orderFrontRegardless()
    }

    /// The window's centre in the top-left-origin coordinates System Events and mouse events use.
    var centerInScreenCoordinates: CGPoint {
        let frame = window.frame
        let screenHeight = NSScreen.screens[0].frame.height
        return CGPoint(x: frame.midX, y: screenHeight - frame.midY)
    }

    func pumpEvents(for seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.01), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
    }

    func close() { window.orderOut(nil); window.close() }
}

final class DragSourceView: NSView, NSDraggingSource {
    private let urls: [URL]
    init(urls: [URL]) { self.urls = urls; super.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseDown(with event: NSEvent) {
        let items = urls.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(bounds, contents: nil)
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [.copy, .generic] }
}
