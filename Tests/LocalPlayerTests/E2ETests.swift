import XCTest
@testable import LocalPlayer
@testable import PlayawayCore

/// End-to-end tests against the built, ad-hoc signed dev bundle, driven from outside through real `open`,
/// `osascript` and `defaults`. They skip unless the bundle exists: run `scripts/run-e2e.sh`, which builds it first.
/// Audio is silenced (volume 0, muted) before anything plays. Nothing here reaches the person's own data: the app is
/// launched against its own bundle id's defaults, and every playlist and audio copy lives in a temp folder.
final class E2ETests: XCTestCase {
    static let bundleID = "com.localplayer.app.e2e"
    /// The e2e bundle has its own name, so it never shares a process, defaults or saved windows with a copy in use.
    static let processName = "LocalPlayerE2E"
    static let scriptTimeout: TimeInterval = 25
    static let launchTimeout: TimeInterval = 20
    var appURL: URL { Fixtures.directory.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/e2e-app/LocalPlayerE2E.app") }
    let dir = TempDir("e2e")

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: appURL.path), "dev bundle not built: run scripts/run-e2e.sh")
        continueAfterFailure = false
        killApp()
        _ = sh("/usr/bin/defaults", ["delete", Self.bundleID])
        clearSavedWindowState()
        _ = sh("/usr/bin/defaults", ["write", Self.bundleID, volumeSettingKey, "-float", "0"])
        _ = sh("/usr/bin/defaults", ["write", Self.bundleID, muteSettingKey, "-bool", "true"])
    }

    /// Windows restored from an earlier run would otherwise change what the first window is.
    func clearSavedWindowState() {
        let saved = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Saved Application State/\(Self.bundleID).savedState")
        try? FileManager.default.removeItem(at: saved)
    }

    override func tearDown() {
        if FileManager.default.fileExists(atPath: appURL.path) {
            killApp()
            _ = sh("/usr/bin/defaults", ["delete", Self.bundleID])
            clearSavedWindowState()
        }
    }

    // MARK: helpers

    @discardableResult
    func sh(_ tool: String, _ args: [String], timeout: TimeInterval = 30) -> (status: Int32, out: String, err: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out; process.standardError = err
        try? process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); return (-999, "", "timeout") }
        let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, o.trimmingCharacters(in: .whitespacesAndNewlines), e.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func killApp() {
        _ = sh("/usr/bin/pkill", ["-x", Self.processName])
        let deadline = Date().addingTimeInterval(5)
        while sh("/usr/bin/pgrep", ["-x", Self.processName]).status == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    }

    /// Launches the app. Windows saved by earlier runs are ignored unless `restoringWindows` is set, so every test
    /// starts from a known first window.
    func launch(opening files: [URL] = [], restoringWindows: Bool = false) throws {
        var args = ["-n", "-g", appURL.path]
        if !restoringWindows { args += ["--args", "-ApplePersistenceIgnoreState", "YES"] }
        let result = sh("/usr/bin/open", args)
        XCTAssertEqual(result.status, 0, result.err)
        if !files.isEmpty {
            // open files through LaunchServices, like a double-click
            _ = sh("/usr/bin/open", ["-g", "-a", appURL.path] + files.map(\.path))
        }
        try waitForApp()
    }

    func waitForApp() throws {
        let deadline = Date().addingTimeInterval(Self.launchTimeout)
        while Date() < deadline {
            if sh("/usr/bin/pgrep", ["-x", Self.processName]).status == 0, osa("get volume").status == 0,
               !osa("get name of every playlist document").out.isEmpty { return }      // ready = the first window is up
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTFail("app did not become scriptable in time")
    }

    /// Runs one AppleScript statement against the app.
    func osa(_ statement: String, timeout: TimeInterval = scriptTimeout) -> (status: Int32, out: String, err: String) {
        sh("/usr/bin/osascript", ["-e", "tell application \"\(appURL.path)\"", "-e", statement, "-e", "end tell"], timeout: timeout)
    }

    /// Runs a statement expected to fail and returns the error number.
    func osaError(_ statement: String) -> Int? {
        let result = sh("/usr/bin/osascript", ["-e", "tell application \"\(appURL.path)\"", "-e", "try", "-e", statement, "-e", "return \"ok\"",
                                               "-e", "on error msg number n", "-e", "return \"error \" & n & \": \" & msg", "-e", "end try", "-e", "end tell"], timeout: Self.scriptTimeout)
        guard result.out.hasPrefix("error ") else { return nil }
        return Int(result.out.dropFirst(6).prefix(while: { $0.isNumber }))
    }

    func waitFor(_ statement: String, equals expected: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if osa(statement).out == expected { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    func audio(_ name: String) -> URL { dir.copyFixture(name) }

    // MARK: bundle declarations (story 1 TC-39, story 4 TC-70/71, story 8 TC-40)

    func testBundleDeclaresExactlyTheThreeAudioTypesAndThePlaylistType() throws {
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: appURL.appendingPathComponent("Contents/Info.plist")), format: nil) as! [String: Any]
        let types = plist["CFBundleDocumentTypes"] as! [[String: Any]]
        let declared = types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        XCTAssertEqual(Set(declared), ["public.mp3", "com.microsoft.waveform-audio", "public.mpeg-4-audio", "com.localplayer.playlist"])
        XCTAssertEqual(declared.count, 4, "nothing else, no flac or video")
        for type in types where (type["LSItemContentTypes"] as? [String]) != ["com.localplayer.playlist"] {
            XCTAssertEqual(type["CFBundleTypeRole"] as? String, "Viewer")
        }
        let playlist = types.first { ($0["LSItemContentTypes"] as? [String]) == ["com.localplayer.playlist"] }!
        XCTAssertEqual(playlist["CFBundleTypeRole"] as? String, "Editor")
        let exported = (plist["UTExportedTypeDeclarations"] as! [[String: Any]])[0]
        XCTAssertEqual(exported["UTTypeIdentifier"] as? String, "com.localplayer.playlist")
        XCTAssertEqual((exported["UTTypeTagSpecification"] as! [String: Any])["public.filename-extension"] as? [String], ["lplaylist"])
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "26.0")
    }

    func testBundleIsSignedAndNotSandboxed() {
        XCTAssertEqual(sh("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path]).status, 0)
        let entitlements = sh("/usr/bin/codesign", ["-d", "--entitlements", "-", appURL.path]).out
        XCTAssertFalse(entitlements.contains("app-sandbox"))
    }

    func testDictionaryListsEveryCommandAndNoDelete() {                                     // E2E-5 at the sdef level
        let result = sh("/usr/bin/sdef", [appURL.path])
        XCTAssertEqual(result.status, 0, result.err)
        for name in ["open audio file", "play track", "pause", "seek", "next track", "previous track", "new playlist",
                     "rename playlist", "add track", "remove track", "move track", "locate track", "check for updates"] {
            XCTAssertTrue(result.out.contains("name=\"\(name)\""), name)
        }
        XCTAssertFalse(result.out.lowercased().contains("delete"))
    }

    // MARK: scripting through the real runtime

    func testGoldenPathScript() throws {                                                     // E2E-1
        try launch()
        let mp3 = audio("long30.mp3")
        XCTAssertEqual(osa("open audio file \"\(mp3.path)\"").status, 0)
        XCTAssertTrue(waitFor("get playing", equals: "true"))
        XCTAssertEqual(osa("get current track").out, "long30.mp3")
        for statement in ["set the volume to 50", "set muted to true", "set muted to false", "set shuffle to true", "set repeat mode to \"all\""] {
            XCTAssertEqual(osa(statement).status, 0, statement)
        }
        XCTAssertEqual(osa("get volume").out, "50")
        XCTAssertEqual(osa("get muted").out, "false")
        XCTAssertEqual(osa("get shuffle").out, "true")
        XCTAssertEqual(osa("get repeat mode").out, "all")
        XCTAssertEqual(osa("pause").status, 0)
        XCTAssertEqual(osa("get playing").out, "false")
        XCTAssertEqual(osa("play").status, 0)
        XCTAssertEqual(osa("get playing").out, "true")
        XCTAssertEqual(osa("seek to 10").status, 0)
        XCTAssertEqual(osa("next track").status, 0, "a single file: nothing happens, no error")
        XCTAssertEqual(osa("stop").status, 0)
        XCTAssertEqual(osa("get playing").out, "false")
    }

    func testErrorsAreNumberedThroughTheRealRuntime() throws {                              // TC-40..48
        try launch()
        XCTAssertEqual(osaError("pause"), 1002)
        XCTAssertEqual(osaError("stop"), 1002)
        XCTAssertEqual(osaError("seek to 3"), 1002)
        XCTAssertEqual(osaError("open audio file \"/no/such/file.mp3\""), 1004)
        XCTAssertEqual(osaError("open audio file \"\(audio("tone.flac").path)\""), 1003)
        XCTAssertEqual(osaError("set the volume to 101"), 1005)
        XCTAssertEqual(osaError("set the volume to -1"), 1005)
        XCTAssertEqual(osaError("remove track 1 from \"Nope\""), 1001)
        XCTAssertEqual(osaError("play track 1 in \"Nope\""), 1001)
        XCTAssertEqual(osaError("set repeat mode to \"sometimes\""), 1005)
        XCTAssertEqual(osa("get volume").out, "0", "refused commands change nothing")
        let message = sh("/usr/bin/osascript", ["-e", "tell application \"\(appURL.path)\" to remove track 1 from \"Morning\""]).err
        XCTAssertTrue(message.contains("No open playlist named Morning"), message)
    }

    func testPlaylistScriptEndToEnd() throws {                                              // E2E-2
        try launch()
        let target = dir.path("Morning.lplaylist")
        XCTAssertEqual(osa("new playlist at \"\(target.path)\"").out, "Morning")
        for name in ["track1.mp3", "tone.wav", "tone.m4a"] {
            XCTAssertEqual(osa("add track \"\(audio(name).path)\" to \"Morning\"").status, 0, name)
        }
        XCTAssertEqual(osa("move track 3 to 1 in \"Morning\"").status, 0)
        XCTAssertEqual(osa("get track count of playlist document \"Morning\"").out, "3")
        XCTAssertEqual(osa("play track 1 in \"Morning\"").status, 0)
        XCTAssertEqual(osa("get current track").out, "tone.m4a", "playback follows the new order")
        XCTAssertEqual(osa("play track 3 in \"Morning\"").status, 0)
        XCTAssertEqual(osa("get current track").out, "tone.wav")
        XCTAssertEqual(osa("remove track 2 from \"Morning\"").status, 0)
        XCTAssertEqual(osa("rename playlist \"Morning\" to \"Evening\"").status, 0)
        XCTAssertTrue(osa("get name of every playlist document").out.contains("Evening"))
        // The autosaved file holds the final state.
        let evening = dir.path("Evening.lplaylist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: evening.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        guard case .loaded(let onDisk) = PlaylistStore().load(from: evening) else { return XCTFail("playlist file unreadable") }
        XCTAssertEqual(onDisk.tracks.map(\.reference.fileName), ["tone.m4a", "tone.wav"])
    }

    func testVolumeAndMuteSurviveQuitAndRelaunchByEitherRoute() throws {                    // TC-88..91 / E2E-7
        try launch()
        XCTAssertEqual(osa("set the volume to 30").status, 0)
        XCTAssertEqual(osa("set muted to true").status, 0)
        XCTAssertEqual(osa("set shuffle to true").status, 0)
        XCTAssertEqual(osa("set repeat mode to \"one\"").status, 0)
        _ = osa("quit")
        let deadline = Date().addingTimeInterval(10)
        while sh("/usr/bin/pgrep", ["-x", Self.processName]).status == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        try launch()
        XCTAssertEqual(osa("get volume").out, "30")
        XCTAssertEqual(osa("get muted").out, "true")
        XCTAssertEqual(osa("get shuffle").out, "true")
        XCTAssertEqual(osa("get repeat mode").out, "one")
        let stored = sh("/usr/bin/defaults", ["read", Self.bundleID, volumeSettingKey]).out
        XCTAssertEqual(Double(stored) ?? -1, 0.3, accuracy: 0.0001)
    }

    func testScriptLaunchesAPlayerThatIsNotRunning() throws {                               // E2E-3
        XCTAssertNotEqual(sh("/usr/bin/pgrep", ["-x", Self.processName]).status, 0)
        let result = sh("/usr/bin/osascript", ["-e", "tell application \"\(appURL.path)\" to get volume"], timeout: 40)
        XCTAssertEqual(result.status, 0, result.err)
        XCTAssertEqual(sh("/usr/bin/pgrep", ["-x", Self.processName]).status, 0, "the script started the app")
    }

    // MARK: Finder-style opens through LaunchServices

    func testOpeningAnAudioFileFromFinderPlaysItAndLeavesItUntouched() throws {              // story 1 E2E-1
        let mp3 = audio("long30.mp3")
        let before = FileSnapshot(mp3)
        try launch(opening: [mp3])
        XCTAssertTrue(waitFor("get current track", equals: "long30.mp3"), "the file plays straight away")
        XCTAssertTrue(waitFor("get playing", equals: "true"))
        XCTAssertEqual(FileSnapshot(mp3), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.url.path), ["long30.mp3"], "no copy anywhere beside it")
        _ = sh("/usr/bin/open", ["-g", "-a", appURL.path, audio("tone.wav").path])
        XCTAssertTrue(waitFor("get current track", equals: "tone.wav"), "a second file replaces the first")
        _ = sh("/usr/bin/open", ["-g", "-a", appURL.path, audio("tone.flac").path])
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(osa("get current track").out, "tone.wav", "unsupported file: playback carries on")
    }

    func testOpeningAPlaylistFromFinderStartsItOnceAndLeavesItAloneWhilePlaying() throws {    // story 3 E2E-1/2
        let fixture = PlaylistFixture(trackNames: ["long30.mp3", "track2.mp3"])
        let url = dir.path("Run.lplaylist")
        XCTAssertEqual(PlaylistStore().save(fixture.playlist, to: url), .saved)
        try launch()
        _ = sh("/usr/bin/open", ["-g", "-a", appURL.path, url.path])
        XCTAssertTrue(waitFor("get current track", equals: "long30.mp3"))
        XCTAssertTrue(waitFor("get playing", equals: "true"))
        XCTAssertEqual(osa("seek to 12").status, 0)
        _ = sh("/usr/bin/open", ["-g", "-a", appURL.path, url.path])
        Thread.sleep(forTimeInterval: 1.5)
        let position = Double(osa("get position").out) ?? 0
        XCTAssertGreaterThanOrEqual(position, 12, "opening it again did not restart it")
        let names = osa("get name of every playlist document").out
        XCTAssertEqual(names.components(separatedBy: ", ").filter { $0 == "Run" }.count, 1, "no second window: \(names)")
    }

    func testFirstWindowAppearsWithoutAnyDialog() throws {
        try launch()
        XCTAssertEqual(osa("get name of every playlist document").out, "Untitled", "a new untitled playlist is the first window")
    }

    // MARK: the real window and menu bar, read through the accessibility tree (System Events)

    /// Runs AppleScript that talks to the app's process through System Events.
    func ax(_ body: String, timeout: TimeInterval = 60) -> (status: Int32, out: String, err: String) {
        sh("/usr/bin/osascript", ["-e", "tell application \"System Events\" to tell process \"\(Self.processName)\"", "-e", body, "-e", "end tell"], timeout: timeout)
    }

    /// The accessibility identifiers of everything in the front window that has one.
    func windowIdentifiers() -> Set<String> {
        let script = """
        set out to ""
        set els to entire contents of window 1
        repeat with e in els
          try
            set out to out & (value of attribute "AXIdentifier" of e) & linefeed
          end try
        end repeat
        return out
        """
        let result = ax(script)
        return Set(result.out.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty && $0 != "missing value" })
    }

    /// Some elements are shown only in some states (the empty hint with no tracks; the track count and the place in
    /// the playlist with some). The check is over the states together, as the spec's "stale" rule is.
    func testRealWindowShowsExactlyTheRecordedElements() throws {                     // story 7 E2E-1 through real accessibility
        try launch()
        let manifest = try UIManifest(data: Data(contentsOf: bundledManifestURL))
        let recorded = Set(manifest.entries[.playlist]!.map(\.elementID))
        let empty = windowIdentifiers()
        XCTAssertTrue(empty.contains("playlist.empty"))
        XCTAssertFalse(empty.contains("playlist.count"), "no count above an empty list")
        XCTAssertFalse(empty.contains("playback.track_position"), "no place in a playlist when nothing plays")
        XCTAssertEqual(osa("add track \"\(audio("long30.mp3").path)\" to \"Untitled\"").status, 0)
        XCTAssertEqual(osa("play track 1 in \"Untitled\"").status, 0)
        XCTAssertTrue(waitFor("get playing", equals: "true"))
        Thread.sleep(forTimeInterval: 0.5)
        let playing = windowIdentifiers()
        XCTAssertTrue(playing.contains("playlist.count"))
        XCTAssertTrue(playing.contains("playback.track_position"))
        XCTAssertFalse(playing.contains("playlist.empty"))
        let seen = empty.union(playing)
        XCTAssertEqual(seen, recorded, "extra: \(seen.subtracting(recorded)), missing: \(recorded.subtracting(seen))")
    }

    func testRealMenuBarAndFileMenu() throws {                                        // story 8 E2E-1
        try launch()
        XCTAssertEqual(ax("get name of every menu bar item of menu bar 1").out, "Apple, \(Self.processName), File, Edit, Window, Help")
        let file = ax("get name of every menu item of menu 1 of menu bar item \"File\" of menu bar 1").out.components(separatedBy: ", ")
        for required in ["New Playlist", "Open…", "Open Recent", "Open Audio File…", "Close", "Save", "Rename…", "Add Files…"] {
            XCTAssertEqual(file.filter { $0 == required }.count, 1, "\(required) exactly once in \(file)")
        }
        XCTAssertFalse(file.contains { $0.lowercased().contains("delete") }, "no Delete Playlist item")
        let edit = ax("get name of every menu item of menu 1 of menu bar item \"Edit\" of menu bar 1").out
        for required in ["Undo", "Redo", "Select All", "Remove from Playlist"] { XCTAssertTrue(edit.contains(required), "Edit has \(required): \(edit)") }
        let app = ax("get name of every menu item of menu 1 of menu bar item \"\(Self.processName)\" of menu bar 1").out
        XCTAssertTrue(app.contains("About LocalPlayer") && app.contains("Quit LocalPlayer") && app.contains("Check for Updates…"), app)
        let quit = ax("get {value of attribute \"AXMenuItemCmdChar\", value of attribute \"AXMenuItemCmdModifiers\"} of menu item \"Quit LocalPlayer\" of menu 1 of menu bar item \"\(Self.processName)\" of menu bar 1").out
        XCTAssertTrue(quit.hasPrefix("Q"), "Command-Q: \(quit)")
        XCTAssertEqual(ax("get name of every menu item of menu 1 of menu bar item \"Help\" of menu bar 1").status, 0)
    }

    func testClickingPlayAndPauseInTheRealWindow() throws {                          // the UI route, for real
        try launch()
        let target = dir.path("Click.lplaylist")
        XCTAssertEqual(osa("new playlist at \"\(target.path)\"").out, "Click")
        for name in ["long30.mp3", "track2.mp3"] { XCTAssertEqual(osa("add track \"\(audio(name).path)\" to \"Click\"").status, 0) }
        // The front window is the new playlist's; press its Play button.
        XCTAssertEqual(ax("tell window \"Click\" to click (first button whose description is \"Play\")").status, 0)
        XCTAssertTrue(waitFor("get playing", equals: "true"))
        XCTAssertEqual(osa("get current track").out, "long30.mp3", "Play starts the playlist from its first track")
        XCTAssertEqual(ax("tell window \"Click\" to click (first button whose description is \"Pause\")").status, 0)
        XCTAssertTrue(waitFor("get playing", equals: "false"), "the control showed Pause while playing and pausing worked")
        XCTAssertEqual(ax("tell window \"Click\" to click (first button whose description is \"Stop\")").status, 0)
        XCTAssertTrue(waitFor("get current track", equals: ""))
    }

    func testMissingTrackShowsTheHazardIconOnlyAfterAPlayIsAttempted() throws {        // story 5 E2E-2 / story 2 E2E-8
        let fixture = PlaylistFixture(trackNames: ["long30.mp3", "track2.mp3", "track3.mp3"])
        let url = dir.path("Gone.lplaylist")
        XCTAssertEqual(PlaylistStore().save(fixture.playlist, to: url), .saved)
        fixture.deleteFile(at: 1)
        try launch()
        _ = sh("/usr/bin/open", ["-g", "-a", appURL.path, url.path])
        XCTAssertTrue(waitFor("get current track", equals: "long30.mp3"), "the playlist plays; the missing track is not asked for yet")
        let hazard = "set n to 0\nset els to entire contents of window \"Gone\"\nrepeat with e in els\ntry\nif description of e is \"Could not be played\" then set n to n + 1\nend try\nend repeat\nreturn n"
        XCTAssertEqual(ax(hazard).out, "0", "no hazard icon until a play is attempted or play-through reaches the track")
        XCTAssertEqual(osaError("play track 2 in \"Gone\""), 1004, "refused, like a double-click")
        XCTAssertEqual(osa("get current track").out, "long30.mp3", "the music carries on")
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(ax(hazard).out, "1", "exactly the missing track shows the hazard icon")
    }

    func testPlaylistWindowsRestoreAfterQuitAndRelaunch() throws {                      // story 6 golden path 2
        try launch(restoringWindows: true)      // ignoring saved state also stops AppKit saving it, so persistence stays on
        let target = dir.path("Restored.lplaylist")
        XCTAssertEqual(osa("new playlist at \"\(target.path)\"").out, "Restored")
        XCTAssertEqual(osa("add track \"\(audio("track1.mp3").path)\" to \"Restored\"").status, 0)
        Thread.sleep(forTimeInterval: 1)
        let before = osa("get name of every playlist document").out.components(separatedBy: ", ").sorted()
        _ = osa("quit")
        let deadline = Date().addingTimeInterval(10)
        while sh("/usr/bin/pgrep", ["-x", Self.processName]).status == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        try launch(restoringWindows: true)
        let names = osa("get name of every playlist document").out
        XCTAssertTrue(names.contains("Restored"), "the playlist windows from last time come back: \(names)")
        XCTAssertEqual(names.components(separatedBy: ", ").sorted(), before, "exactly the windows that were open come back, no extra untitled one")
    }

    func testSpaceBarTogglesPlayPauseInTheRealWindow() throws {                          // a real keystroke, not a method call
        try launch()
        XCTAssertEqual(osa("open audio file \"\(audio("long30.mp3").path)\"").status, 0)
        XCTAssertTrue(waitFor("get playing", equals: "true"))
        _ = ax("set frontmost to true")
        Thread.sleep(forTimeInterval: 1)
        for expected in ["false", "true", "false"] {
            XCTAssertEqual(sh("/usr/bin/osascript", ["-e", "tell application \"System Events\" to keystroke \" \""]).status, 0)
            XCTAssertTrue(waitFor("get playing", equals: expected, timeout: 4), "Space should leave playing = \(expected)")
        }
    }
}
