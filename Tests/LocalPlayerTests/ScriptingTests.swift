import XCTest
import AppKit
@testable import LocalPlayer
@testable import PlayawayCore

let sdefURL = Fixtures.directory.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LocalPlayer.sdef")
let infoPlistURL = Fixtures.directory.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Info.plist")

/// A snapshot of everything a person could observe, to compare the UI route with the script route.
struct StateSnapshot: Equatable {
    var playing: Bool
    var current: String
    var position: Double
    var volume: Int
    var muted: Bool
    var shuffle: Bool
    var repeatMode: String
    var playlists: [String: [String]]
    var startedNames: [String]
    var savedVolume: Double?
    var savedMuted: Bool?
    var savedShuffle: Bool?
    var savedRepeat: String?
    var fileNames: [String]
    /// Which open playlists have iCloud sync on (story 18).
    var synced: [String: Bool] = [:]
}

@MainActor
final class ScriptActionsTests: XCTestCase {
    var app: TestApp!
    var actions: AppActions!
    let dir = TempDir("script")
    let audio = TempDir("scriptaudio")
    var keep: [PlaylistFixture] = []

    override func setUp() async throws { try makeApp() }
    override func tearDown() async throws { app.tearDown() }

    func makeApp() throws {
        app = TestApp()
        actions = AppActions(services: app.services)
        actions.isReady = { true }
        actions.defaultSaveDirectory = dir.url
    }

    func openPlaylist(_ names: [String] = Fixtures.trackNames, as name: String = "Morning") -> PlaylistDocument {
        let fixture = PlaylistFixture(trackNames: names)
        keep.append(fixture)
        return app.openSaved(fixture.playlist, at: dir.path("\(name).lplaylist"))
    }

    func expectFailure(_ number: Int, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) {
        do { try body(); XCTFail("expected error \(number)", file: file, line: line) } catch let failure as ScriptFailure {
            XCTAssertEqual(failure.number, number, failure.message, file: file, line: line)
            XCTAssertFalse(failure.message.isEmpty, "a plain-language message", file: file, line: line)
        } catch { XCTFail("unexpected \(error)", file: file, line: line) }
    }

    func snapshot() -> StateSnapshot {
        let defaults = app.services.defaults
        var playlists: [String: [String]] = [:]
        for doc in app.controller.playlistDocuments { playlists[doc.displayName] = doc.playlist.tracks.map(\.reference.fileName) }
        return StateSnapshot(playing: actions.isPlaying, current: actions.currentTrackName, position: actions.position,
                             volume: actions.volumePercent, muted: actions.isMuted, shuffle: actions.shuffleOn, repeatMode: actions.repeatName,
                             playlists: playlists, startedNames: app.backend.startedNames,
                             savedVolume: defaults.object(forKey: volumeSettingKey) as? Double,
                             savedMuted: defaults.object(forKey: muteSettingKey) as? Bool,
                             savedShuffle: defaults.object(forKey: shuffleSettingKey) as? Bool,
                             savedRepeat: defaults.object(forKey: repeatSettingKey) as? String,
                             fileNames: ((try? FileManager.default.contentsOfDirectory(atPath: dir.url.path)) ?? []).sorted())
    }

    // MARK: errors (TC-40..TC-49, TC-56, TC-84..TC-86)

    func testNamingAPlaylistThatIsNotOpenIs1001WithAPlainMessage() {                   // TC-40 / TC-86
        let before = snapshot()
        expectFailure(1001) { try actions.addTrack(path: Fixtures.url("track1.mp3").path, toPlaylist: "Morning") }
        expectFailure(1001) { try actions.removeTrack(1, fromPlaylist: "Morning") }
        expectFailure(1001) { try actions.renamePlaylist("Morning", to: "Evening") }
        expectFailure(1001) { try actions.playTrack(1, inPlaylist: "Morning") }
        expectFailure(1001) { try actions.moveTrack(1, to: 2, inPlaylist: "Morning") }
        expectFailure(1001) { try actions.locateTrack(1, inPlaylist: "Morning", withFile: "/x.mp3") }
        XCTAssertThrowsError(try actions.removeTrack(1, fromPlaylist: "Morning")) {
            XCTAssertEqual(($0 as? ScriptFailure)?.message, "No open playlist named Morning") }
        XCTAssertEqual(snapshot(), before)
    }

    func testNothingPlayingIs1002() {                                                   // TC-41
        expectFailure(1002) { try actions.pause() }
        expectFailure(1002) { try actions.stop() }
        expectFailure(1002) { try actions.seek(toSeconds: 1) }
        expectFailure(1002) { try actions.next() }
        expectFailure(1002) { try actions.previous() }
        expectFailure(1002) { try actions.play() }
    }

    func testUnsupportedFileIs1003WithTheOnScreenWording() {                            // TC-42
        _ = app.services.engine.play(Fixtures.url("track1.mp3"))
        let before = snapshot()
        XCTAssertThrowsError(try actions.openFile(path: Fixtures.url("tone.flac").path)) {
            let failure = $0 as! ScriptFailure
            XCTAssertEqual(failure.number, 1003)
            XCTAssertTrue(failure.message.contains("not supported yet"))
            XCTAssertEqual(failure.message, self.app.notices.shown.last?.fullText, "the same explanation the person would see")
        }
        XCTAssertEqual(snapshot(), before, "playback unchanged")
    }

    func testMissingFileIs1004() {                                                       // TC-43
        let before = snapshot()
        expectFailure(1004) { try actions.openFile(path: "/no/such/file.mp3") }
        expectFailure(1004) { try actions.openFile(path: "") }
        XCTAssertEqual(snapshot(), before)
    }

    func testOutOfRangeSeekAndVolumeAre1005() {                                           // TC-44 / TC-45
        _ = app.services.engine.play(Fixtures.url("track1.mp3"))
        for bad in [-1.0, 5.0] {
            let before = snapshot()
            expectFailure(1005) { try actions.seek(toSeconds: bad) }
            XCTAssertEqual(snapshot(), before)
        }
        try? actions.setVolume(percent: 30)
        for bad in [-1, 101] {
            expectFailure(1005) { try actions.setVolume(percent: bad) }
            XCTAssertEqual(actions.volumePercent, 30)
        }
        expectFailure(1005) { try actions.setRepeat("sometimes") }
    }

    func testNoSuchTrackIs1006() {                                                        // TC-46 / TC-84
        let doc = openPlaylist()
        let before = doc.playlist
        for bad in [0, 6, -1] {
            expectFailure(1006) { try actions.removeTrack(bad, fromPlaylist: "Morning") }
            expectFailure(1006) { try actions.playTrack(bad, inPlaylist: "Morning") }
        }
        expectFailure(1006) { try actions.moveTrack(1, to: 6, inPlaylist: "Morning") }
        XCTAssertEqual(doc.playlist, before)
        XCTAssertTrue(app.backend.log.isEmpty)
    }

    func testLocateFailures1007() {                                                       // TC-47
        let doc = openPlaylist()
        let present = audio.copyFixture("track2.mp3")
        expectFailure(1007) { try actions.locateTrack(1, inPlaylist: "Morning", withFile: present.path) }   // track is not missing
        keep.last!.deleteFile(at: 1)
        var done = false; doc.resolveStatuses { done = true }; spin { done }
        expectFailure(1007) { try actions.locateTrack(2, inPlaylist: "Morning", withFile: "/no/such.mp3") }
        XCTAssertEqual(doc.statuses.status(of: doc.playlist.tracks[1].id), .missing, "track stays greyed")
    }

    func testNotReadyIs1008AndChangesNothing() {                                          // TC-48
        actions.isReady = { false }
        let before = snapshot()
        expectFailure(1008) { try actions.play() }
        expectFailure(1008) { try actions.openFile(path: Fixtures.url("track1.mp3").path) }
        expectFailure(1008) { try actions.setVolume(percent: 5) }
        expectFailure(1008) { _ = try actions.newPlaylist(named: nil, atPath: nil) }
        XCTAssertEqual(snapshot(), before)
    }

    func testCheckForUpdatesBeforeTheServiceStartedIs1008() {                              // TC-49
        actions.updater = UpdaterController(configuration: UpdateConfiguration(feedURL: "", publicEDKey: "", automaticChecksEnabled: nil))
        expectFailure(1008) { try actions.checkForUpdates() }
    }

    func testPlayingATrackWhoseFileIsMissingIs1004AndPlaysNothing() {                      // TC-85
        let doc = openPlaylist()
        keep.last!.deleteFile(at: 2)
        _ = doc
        expectFailure(1004) { try actions.playTrack(3, inPlaylist: "Morning") }
        XCTAssertTrue(app.backend.log.isEmpty)
        XCTAssertTrue(app.notices.shown.isEmpty, "no dialog")
    }

    func testPlayTrackFirstAndLastAndReplacement() throws {                                // TC-78 / TC-87
        _ = openPlaylist()
        try actions.playTrack(1, inPlaylist: "Morning")
        XCTAssertEqual(actions.currentTrackName, "track1.mp3")
        XCTAssertEqual(actions.position, 0)
        try actions.playTrack(5, inPlaylist: "Morning")
        XCTAssertEqual(actions.currentTrackName, "track5.mp3")
        XCTAssertEqual(app.backend.players.filter(\.running).count, 1, "only one thing plays at a time")
    }

    func testRefusedCommandsNeverDeleteAnything() {                                         // TC-74 / TC-70
        let doc = openPlaylist()
        let files = doc.playlist.tracks.count
        try? actions.removeTrack(1, fromPlaylist: "Morning")
        XCTAssertEqual(doc.playlist.tracks.count, files - 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: keep.last!.dir.url.path).count, 5, "audio files untouched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: doc.fileURL!.path), "playlist file untouched")
    }

    // MARK: transport and modes

    func testTransportCommandsMatchTheControls() throws {                                   // TC-50..52
        _ = openPlaylist()
        try actions.playTrack(2, inPlaylist: "Morning")
        try actions.seek(toSeconds: 0); XCTAssertEqual(actions.position, 0)
        try actions.seek(toSeconds: 4); XCTAssertEqual(actions.position, 4)
        try actions.setVolume(percent: 0); XCTAssertEqual(app.services.engine.volume, 0.0)
        try actions.setVolume(percent: 100); XCTAssertEqual(app.services.engine.volume, 1.0)
        try actions.setMuted(true); try actions.setMuted(true)
        XCTAssertTrue(actions.isMuted)
        XCTAssertEqual(actions.volumePercent, 100, "muting leaves the volume value")
        try actions.pause(); XCTAssertFalse(actions.isPlaying)
        try actions.play(); XCTAssertTrue(actions.isPlaying)
        try actions.next(); XCTAssertEqual(actions.currentTrackName, "track3.mp3")
        try actions.previous(); XCTAssertEqual(actions.currentTrackName, "track2.mp3")
        try actions.stop(); XCTAssertEqual(actions.currentTrackName, "")
    }

    func testPreviousAtTheEdgesFollowsTheControl() throws {                                 // TC-80..TC-83
        _ = openPlaylist(["track1.mp3", "track2.mp3", "track3.mp3"])
        try actions.playTrack(1, inPlaylist: "Morning")
        try actions.previous()
        XCTAssertEqual(actions.currentTrackName, "track1.mp3", "repeat off: nothing changes")
        try actions.setRepeat("all")
        try actions.previous()
        XCTAssertEqual(actions.currentTrackName, "track3.mp3")
    }

    func testStateReadsAreSideEffectFree() throws {                                          // TC-57 / TC-71
        let idle = snapshot()
        _ = (actions.isPlaying, actions.currentTrackName, actions.position, actions.volumePercent, actions.isMuted, actions.shuffleOn, actions.repeatName, actions.playlistNames)
        XCTAssertEqual(snapshot(), idle)
        XCTAssertEqual(actions.playlistNames, [], "no playlists open lists nothing, not an error")
        XCTAssertEqual(idle.volume, 100); XCTAssertFalse(idle.playing); XCTAssertEqual(idle.current, "")
        _ = openPlaylist()
        try actions.playTrack(1, inPlaylist: "Morning")
        let playing = snapshot()
        _ = (actions.isPlaying, actions.currentTrackName, actions.position)
        XCTAssertEqual(snapshot(), playing)
        XCTAssertEqual(actions.playlistNames, ["Morning"])
    }

    func testVolumeAndMuteAreSavedByScriptTheSameWayAsByControl() throws {                  // TC-79 / TC-88..91
        try actions.setVolume(percent: 30)
        try actions.setMuted(true)
        let relaunched = AVPlaybackEngine(backend: RecordingAudioBackend(), devices: StubOutputDevices(hasOutputDevice: true),
                                          settings: VolumeSettingsStore(defaults: app.services.defaults))
        XCTAssertEqual(relaunched.volume, 0.3)
        XCTAssertTrue(relaunched.isMuted)
        try actions.setShuffle(true); try actions.setRepeat("one")
        let modes = PlayModeSettings(store: PlayModeStore(defaults: app.services.defaults))
        XCTAssertTrue(modes.shuffleOn); XCTAssertEqual(modes.repeatMode, .one)
    }

    // MARK: playlists

    func testNewPlaylistVariants() throws {                                                   // TC-24 / TC-54..56
        _ = try actions.newPlaylist(named: nil, atPath: nil)
        XCTAssertEqual(app.controller.playlistDocuments.count, 1)
        XCTAssertNil(app.controller.playlistDocuments[0].fileURL, "neither name nor path: stays untitled")
        let name = try actions.newPlaylist(named: "Morning", atPath: nil)
        XCTAssertEqual(name, "Morning")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path("Morning.lplaylist").path))
        let elsewhere = dir.makeSubfolder("elsewhere")
        _ = try actions.newPlaylist(named: nil, atPath: elsewhere.appendingPathComponent("Run.lplaylist").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent("Run.lplaylist").path))
        let locked = dir.makeSubfolder("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        let docsBefore = app.controller.playlistDocuments.count
        expectFailure(1005) { _ = try actions.newPlaylist(named: nil, atPath: locked.appendingPathComponent("X.lplaylist").path) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: locked.appendingPathComponent("X.lplaylist").path))
        XCTAssertEqual(app.controller.playlistDocuments.count, docsBefore, "no document left behind")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        expectFailure(1005) { _ = try actions.newPlaylist(named: "Morning", atPath: nil) }       // never overwrites a file
    }

    func testAddRemoveMoveAndRenameThroughActions() throws {                                   // TC-26..32, TC-53
        _ = try actions.newPlaylist(named: "Morning", atPath: nil)
        for name in ["track1.mp3", "tone.wav", "tone.m4a"] {
            try actions.addTrack(path: audio.copyFixture(name).path, toPlaylist: "Morning")
        }
        let doc = try actions.document(named: "Morning")
        XCTAssertEqual(doc.playlist.tracks.map(\.reference.fileName), ["track1.mp3", "tone.wav", "tone.m4a"])
        try actions.moveTrack(3, to: 1, inPlaylist: "Morning")
        XCTAssertEqual(doc.playlist.tracks.map(\.reference.fileName), ["tone.m4a", "track1.mp3", "tone.wav"])
        try actions.moveTrack(2, to: 2, inPlaylist: "Morning")                                     // no-op, not an error
        try actions.removeTrack(1, fromPlaylist: "Morning")
        XCTAssertEqual(doc.playlist.tracks.count, 2)
        expectFailure(1003) { try actions.addTrack(path: Fixtures.url("tone.flac").path, toPlaylist: "Morning") }
        expectFailure(1004) { try actions.addTrack(path: "/no/such.mp3", toPlaylist: "Morning") }
        try actions.renamePlaylist("Morning", to: "Evening")
        XCTAssertEqual(doc.displayName, "Evening")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path("Evening.lplaylist").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path("Morning.lplaylist").path))
        expectFailure(1001) { try actions.renamePlaylist("Morning", to: "Again") }
    }

    func testLocateTrackRepairsAndReconnectsTheFolder() throws {                                // TC-34
        let doc = openPlaylist()
        let home = TempDir("home")
        for index in [1, 3] { keep.last!.deleteFile(at: index) }
        _ = home.copyFixture("track2.mp3"); _ = home.copyFixture("track4.mp3")
        var done = false; doc.resolveStatuses { done = true }; spin { done }
        try actions.locateTrack(2, inPlaylist: "Morning", withFile: home.path("track2.mp3").path)
        XCTAssertEqual(doc.statuses.status(of: doc.playlist.tracks[1].id), .resolved(home.path("track2.mp3")))
        XCTAssertEqual(doc.statuses.status(of: doc.playlist.tracks[3].id), .resolved(home.path("track4.mp3")))
        try actions.playTrack(2, inPlaylist: "Morning")
        XCTAssertEqual(actions.currentTrackName, "track2.mp3")
    }

    func testOpenFileScriptsLikeFinder() throws {                                               // TC-02 / TC-75
        _ = app.services.engine.play(Fixtures.url("track5.mp3"))
        try actions.openFile(path: Fixtures.url("tone.wav").path)
        XCTAssertEqual(actions.currentTrackName, "tone.wav")
        XCTAssertEqual(actions.position, 0)
        XCTAssertEqual(app.backend.players.filter(\.running).count, 1)
        XCTAssertTrue(app.notices.shown.isEmpty, "no import step, library prompt or confirmation")
    }
}

final class SdefAndParityTests: XCTestCase {
    var sdefData: Data { try! Data(contentsOf: sdefURL) }

    func testSdefParsesAndEveryEntryHasADescription() throws {                                   // TC-59
        final class Delegate: NSObject, XMLParserDelegate {
            var missing: [String] = []
            func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
                if ["command", "property"].contains(name), (a["description"] ?? "").isEmpty { missing.append(a["name"] ?? "?") }
            }
        }
        let parser = XMLParser(data: sdefData)
        let delegate = Delegate(); parser.delegate = delegate
        XCTAssertTrue(parser.parse())
        XCTAssertTrue(delegate.missing.isEmpty, "no description: \(delegate.missing)")
    }

    func testInfoPlistTurnsScriptingOnAndNamesTheSdef() throws {                                 // TC-60
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoPlistURL), format: nil) as! [String: Any]
        XCTAssertEqual(plist["NSAppleScriptEnabled"] as? Bool, true)
        XCTAssertEqual(plist["OSAScriptingDefinition"] as? String, "LocalPlayer.sdef")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sdefURL.path))
    }

    func testNoDeleteCommandAndNoSystemItemEntries() {                                            // TC-76 / TC-77
        let text = String(data: sdefData, encoding: .utf8)!.lowercased()
        XCTAssertFalse(text.contains("delete"))
        XCTAssertFalse(text.contains("remove playlist"))
        for system in ["name=\"quit\"", "name=\"about", "name=\"hide", "name=\"services", "name=\"window", "name=\"help"] {
            XCTAssertFalse(text.contains(system), system)
        }
    }

    func testNineteenActionsAndTheGatePasses() {                                                  // TC-63 / TC-68
        XCTAssertEqual(ActionManifest.actions.count, 20)
        XCTAssertEqual(Set(ActionManifest.actions.map(\.id)).count, 20)
        let entries = ParityGate.dictionaryEntries(sdef: sdefData)
        let result = ParityGate.checkParity(manifest: ActionManifest.actions, dictionaryEntries: entries, excluded: ExcludedSystemItems.ids)
        XCTAssertTrue(result.passed, "\(result)")
    }

    func testGateFailsNamingAnActionWithNoScriptEntry() {                                         // TC-61
        var entries = ParityGate.dictionaryEntries(sdef: sdefData)
        entries.remove("seek")
        let result = ParityGate.checkParity(manifest: ActionManifest.actions, dictionaryEntries: entries, excluded: ExcludedSystemItems.ids)
        XCTAssertEqual(result.missingScript, ["seek"])
    }

    func testGateFailsNamingAScriptEntryWithNoUIAction() {                                        // TC-62 / TC-72
        var entries = ParityGate.dictionaryEntries(sdef: sdefData)
        entries.insert("shuffle the deck")
        let result = ParityGate.checkParity(manifest: ActionManifest.actions, dictionaryEntries: entries, excluded: ExcludedSystemItems.ids)
        XCTAssertEqual(result.missingUI, ["shuffle the deck"])
    }

    func testExcludedSystemItemsNeedNoScriptEntry() {                                             // TC-64
        let manifest = ActionManifest.actions + ["about", "quit", "hide", "services", "windowMenu", "helpMenu"].map {
            ManifestAction(id: $0, description: "", uiBinding: "system", scriptBinding: nil) }
        let result = ParityGate.checkParity(manifest: manifest, dictionaryEntries: ParityGate.dictionaryEntries(sdef: sdefData), excluded: ExcludedSystemItems.ids)
        XCTAssertTrue(result.passed)
        let unexcluded = ParityGate.checkParity(manifest: manifest, dictionaryEntries: ParityGate.dictionaryEntries(sdef: sdefData), excluded: [])
        XCTAssertFalse(unexcluded.passed)
    }

    func testAppSpecificMenuItemWithoutBindingFails() {                                           // TC-65
        let menu = NSMenu()
        let file = NSMenuItem(title: "File", action: nil, keyEquivalent: ""); let sub = NSMenu(title: "File")
        sub.addItem(NSMenuItem(title: "Export to Cloud…", action: nil, keyEquivalent: "")); file.submenu = sub; menu.addItem(file)
        XCTAssertEqual(ParityGate.menuItemsWithoutScriptBinding(in: menu, manifest: ActionManifest.actions), ["Export to Cloud…"])
    }

    @MainActor func testTheRealMenuBarHasNoUnboundAppSpecificItems() {
        let menu = AppMenu.makeMenuBar(target: nil)
        XCTAssertEqual(ParityGate.menuItemsWithoutScriptBinding(in: menu, manifest: ActionManifest.actions), [])
    }

    func testEveryCommandClassNamedInTheSdefExists() throws {
        let text = String(data: sdefData, encoding: .utf8)!
        let regex = try NSRegularExpression(pattern: #"<cocoa class="(\w+)"/>"#)
        let names = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range(at: 1), in: text)!]) }
        XCTAssertGreaterThanOrEqual(names.count, 15)
        for name in names where name != "NSApplication" {
            XCTAssertNotNil(NSClassFromString(name), "\(name) must exist as an Objective-C class")
        }
    }

    func testKVCKeysAreWhitelistedAndExist() {                                                     // TC-58
        for key in AppDelegate.scriptKVCKeys { XCTAssertTrue(sdefTextContains(key), key) }
        XCTAssertFalse(AppDelegate.scriptKVCKeys.contains("scriptDeleteEverything"))
    }

    func sdefTextContains(_ key: String) -> Bool { String(data: sdefData, encoding: .utf8)!.contains("key=\"\(key)\"") }
}
