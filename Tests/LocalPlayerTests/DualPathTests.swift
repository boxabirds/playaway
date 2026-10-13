import XCTest
import AppKit
@testable import LocalPlayer
@testable import PlayawayCore

/// Every app-specific action, triggered through the on-screen route and through the script route, in two fresh apps
/// that start from the same fixture. The observable result must be identical. (scripting.tests.dual_path)
@MainActor
final class DualPathTests: XCTestCase {
    enum Route { case ui, script }

    /// One fresh app with a saved three-track playlist named Morning, so both routes start from the same state.
    @MainActor final class Rig {
        let app: TestApp
        let actions: AppActions
        let dir = TempDir("dual")
        let audio = TempDir("dualaudio")
        let fixture = PlaylistFixture(trackNames: ["track1.mp3", "track2.mp3", "track3.mp3"])
        var doc: PlaylistDocument!
        var transportView: TransportControlsView!
        var modes: PlayModeControls!
        var window: PlaylistWindowController { app.window(of: doc) }
        var updateChecks = 0

        init(withPlaylist: Bool = true) {
            app = TestApp()
            actions = AppActions(services: app.services)
            actions.isReady = { true }
            actions.defaultSaveDirectory = dir.url
            if withPlaylist { doc = app.openSaved(fixture.playlist, at: dir.path("Morning.lplaylist")) }
            transportView = TransportControlsView(viewModel: app.services.transport)
            modes = PlayModeControls(settings: app.services.settings)
        }

        func startPaused() throws { try actions.playTrack(2, inPlaylist: "Morning"); try actions.pause() }
        func startPlaying() throws { try actions.playTrack(2, inPlaylist: "Morning") }

        func snapshot() -> StateSnapshot {
            var playlists: [String: [String]] = [:]
            for doc in app.controller.playlistDocuments {
                playlists[doc.displayName] = doc.playlist.tracks.map { track in
                    let state = doc.statuses.status(of: track.id).map { $0 == .missing ? "missing" : "resolved" } ?? "unknown"
                    return "\(track.reference.fileName):\(state)"
                }
            }
            let defaults = app.services.defaults
            return StateSnapshot(playing: actions.isPlaying, current: actions.currentTrackName, position: actions.position,
                                 volume: actions.volumePercent, muted: actions.isMuted, shuffle: actions.shuffleOn, repeatMode: actions.repeatName,
                                 playlists: playlists, startedNames: app.backend.startedNames,
                                 savedVolume: defaults.object(forKey: volumeSettingKey) as? Double,
                                 savedMuted: defaults.object(forKey: muteSettingKey) as? Bool,
                                 savedShuffle: defaults.object(forKey: shuffleSettingKey) as? Bool,
                                 savedRepeat: defaults.object(forKey: repeatSettingKey) as? String,
                                 fileNames: ((try? FileManager.default.contentsOfDirectory(atPath: dir.url.path)) ?? []).sorted())
        }
    }

    /// Runs one action on one route and returns what a person would see afterwards.
    func perform(_ action: String, _ route: Route) throws -> StateSnapshot {
        let rig = Rig(withPlaylist: action != "newPlaylist")
        defer { rig.app.tearDown() }
        let wav = rig.audio.copyFixture("tone.wav")
        switch (action, route) {
        case ("openFile", .ui): rig.app.services.openCoordinator.open(wav)                 // File > Open Audio File… hands the chosen URL over
        case ("openFile", .script): try rig.actions.openFile(path: wav.path)

        case ("play", .ui): try rig.startPaused(); rig.transportView.playPausePressed()
        case ("play", .script): try rig.startPaused(); try rig.actions.play()

        case ("playTrack", .ui): rig.window.playRow(1)
        case ("playTrack", .script): try rig.actions.playTrack(2, inPlaylist: "Morning")

        case ("pause", .ui): try rig.startPlaying(); rig.transportView.playPausePressed()
        case ("pause", .script): try rig.startPlaying(); try rig.actions.pause()

        case ("stop", .ui): try rig.startPlaying(); rig.transportView.stopPressed()
        case ("stop", .script): try rig.startPlaying(); try rig.actions.stop()

        case ("seek", .ui): try rig.startPlaying(); rig.transportView.render(); rig.transportView.positionSlider.doubleValue = 2; rig.transportView.positionChanged()
        case ("seek", .script): try rig.startPlaying(); try rig.actions.seek(toSeconds: 2)

        case ("next", .ui): try rig.startPlaying(); rig.transportView.nextPressed()
        case ("next", .script): try rig.startPlaying(); try rig.actions.next()

        case ("previous", .ui): try rig.startPlaying(); rig.transportView.previousPressed()
        case ("previous", .script): try rig.startPlaying(); try rig.actions.previous()

        case ("volume", .ui): rig.transportView.volumeSlider.doubleValue = 0.5; rig.transportView.volumeChanged()
        case ("volume", .script): try rig.actions.setVolume(percent: 50)

        case ("mute", .ui): rig.transportView.mutePressed()
        case ("mute", .script): try rig.actions.setMuted(true)

        case ("shuffle", .ui): rig.modes.shufflePressed()
        case ("shuffle", .script): try rig.actions.setShuffle(true)

        case ("repeat", .ui): rig.modes.repeatPressed()
        case ("repeat", .script): try rig.actions.setRepeat("all")

        case ("newPlaylist", .ui): _ = try rig.app.controller.openUntitledDocumentAndDisplay(true)
        case ("newPlaylist", .script): try rig.actions.newPlaylist(named: nil, atPath: nil).description.isEmpty ? () : ()

        case ("renamePlaylist", .ui):
            var done = false; rig.doc.renameFile(to: "Evening") { _ in done = true }; spin { done }
        case ("renamePlaylist", .script): try rig.actions.renamePlaylist("Morning", to: "Evening")

        case ("addTrack", .ui): rig.window.chooseFilesToAdd = { [wav] in [wav] }; rig.window.addFiles(nil)
        case ("addTrack", .script): try rig.actions.addTrack(path: wav.path, toPlaylist: "Morning")

        case ("removeTrack", .ui): rig.window.tableView.selectRowIndexes([0], byExtendingSelection: false); rig.window.removeSelectedTracks(nil)
        case ("removeTrack", .script): try rig.actions.removeTrack(1, fromPlaylist: "Morning")

        case ("reorderTrack", .ui): _ = rig.window.reorder(rows: [2], toBefore: 0)
        case ("reorderTrack", .script): try rig.actions.moveTrack(3, to: 1, inPlaylist: "Morning")

        case ("locate", .ui, ), ("locate", .script):
            let home = rig.audio.makeSubfolder("home")
            let moved = home.appendingPathComponent("track2.mp3")
            try FileManager.default.copyItem(at: Fixtures.url("track2.mp3"), to: moved)
            rig.fixture.deleteFile(at: 1)
            var done = false; rig.doc.resolveStatuses { done = true }; spin { done }
            if route == .ui {
                rig.window.chooseFileToLocate = { moved }
                let item = NSMenuItem(); item.representedObject = rig.doc.playlist.tracks[1].id
                rig.window.locateTrack(item)
            } else {
                try rig.actions.locateTrack(2, inPlaylist: "Morning", withFile: moved.path)
            }

        case ("checkForUpdates", _): return rig.snapshot()      // compared on the updater's own state, see testCheckForUpdates...

        default: XCTFail("no scenario for \(action) on \(route)")
        }
        return rig.snapshot()
    }

    /// Every action the manifest lists has a case; adding one without a case fails this test (TC-67 / TC-68).
    static let covered: Set<String> = ["openFile", "play", "playTrack", "pause", "stop", "seek", "next", "previous", "volume", "mute",
                                       "shuffle", "repeat", "newPlaylist", "renamePlaylist", "addTrack", "removeTrack", "reorderTrack",
                                       "locate", "checkForUpdates"]

    func testEveryManifestActionHasADualRouteCase() {
        XCTAssertEqual(Set(ActionManifest.actions.map(\.id)), Self.covered, "an action without a dual-route case fails the suite")
        XCTAssertEqual(Self.covered.count, 19, "19 UI cases and 19 script cases")
    }

    func testBothRoutesGiveTheSameResultForEveryAction() throws {
        for action in ActionManifest.actions.map(\.id) {
            let viaUI = try perform(action, .ui)
            let viaScript = try perform(action, .script)
            XCTAssertEqual(viaUI, viaScript, "\(action): the click and the script differ")
        }
    }

    /// Check for Updates: the menu item's target and the script command both start exactly one check (TC-35 / TC-36),
    /// and both are refused the same way while the update service has not started (TC-49).
    func testCheckForUpdatesStartsOneCheckByEitherRoute() throws {
        func rig(started: Bool) -> (StubUpdaterDriver, UpdaterController, AppActions, AppDelegate) {
            let app = TestApp()
            let driver = StubUpdaterDriver()
            let controller = UpdaterController(configuration: UpdateConfiguration(
                feedURL: "https://updates.example.test/appcast.xml", publicEDKey: String(repeating: "A", count: 44), automaticChecksEnabled: true),
                driverFactory: { driver })
            if started { controller.startAfterFirstWindow() }
            let actions = AppActions(services: app.services)
            actions.isReady = { true }
            actions.updater = controller
            let delegate = AppDelegate()
            delegate.updater = controller
            delegate.actions = actions
            return (driver, controller, actions, delegate)
        }
        let ui = rig(started: true)
        ui.3.checkForUpdates(nil)
        XCTAssertEqual(ui.0.checkCalls, 1, "the menu item starts one check")
        let script = rig(started: true)
        try script.2.checkForUpdates()
        XCTAssertEqual(script.0.checkCalls, 1, "the script starts the same one check")
        try script.2.checkForUpdates()
        XCTAssertEqual(script.0.checkCalls, 1, "no second check while one is running, the same guard as the menu")
        let notStarted = rig(started: false)
        notStarted.3.checkForUpdates(nil)
        XCTAssertThrowsError(try notStarted.2.checkForUpdates()) { XCTAssertEqual(($0 as? ScriptFailure)?.number, 1008) }
        XCTAssertEqual(notStarted.0.checkCalls, 0, "no check starts before the service has")
    }

    func testTheScenariosActuallyChangeSomethingSoTheComparisonIsNotVacuous() throws {
        let baseline = try perform("checkForUpdates", .ui)
        for action in ActionManifest.actions.map(\.id) where !["checkForUpdates", "play", "pause"].contains(action) {
            XCTAssertNotEqual(try perform(action, .ui), baseline, "\(action) produced no visible change")
        }
    }

    func testKnownResultsOfSomeRoutes() throws {
        XCTAssertEqual(try perform("reorderTrack", .script).playlists["Morning"]?.map { $0.split(separator: ":")[0] },
                       ["track3.mp3", "track1.mp3", "track2.mp3"])                                        // TC-31/32
        XCTAssertEqual(try perform("volume", .ui).volume, 50)                                             // TC-15/16
        XCTAssertEqual(try perform("repeat", .script).savedRepeat, "all")                                 // TC-21/22
        XCTAssertEqual(try perform("seek", .ui).position, 2)                                              // TC-09/10
        XCTAssertEqual(try perform("locate", .script).playlists["Morning"]?[1], "track2.mp3:resolved")    // TC-33/34
    }
}
