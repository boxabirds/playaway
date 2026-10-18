import XCTest
import AppKit
import CryptoKit
@testable import LocalPlayer
@testable import PlayawayCore

/// End-to-end gap tests for task 9.25 (Check for Updates by script and by menu) and task 8.11 (real appearance
/// switch, accessibility settings left untouched). They drive the built, ad-hoc signed dev bundle from outside through
/// `open`, `osascript`, System Events and `screencapture`, exactly like E2ETests, and follow its conventions:
/// they skip unless the bundle exists. They are NOT run by `scripts/run-e2e.sh` (that filters to E2ETests).
///
/// They put windows on screen and one switches the system appearance, so every test here also skips unless
/// `LP_GUI_E2E_APPROVED=1` is set, which the owner sets when giving permission to run them:
///   LP_GUI_E2E_APPROVED=1 swift test --filter E2EGapTests   (after scripts/run-e2e.sh has built the bundle)
///
/// Updates: the dev bundle ships a placeholder feed URL and public key, so the updater would stay disabled. The tests
/// therefore use a COPY of the bundle with a valid-looking feed URL and a throwaway public key, ad-hoc re-signed in a
/// temp folder, and point the debug-only feed override (LOCALPLAYER_TEST_FEED_URL) at a local fixture server. The
/// real bundle is not modified, no update is ever chosen, and nothing is downloaded or installed.
final class E2EGapTests: XCTestCase {
    static let approvalKey = "LP_GUI_E2E_APPROVED"
    static let approvedValue = "1"
    static let bundleID = E2ETests.bundleID
    static let processName = E2ETests.processName
    static let scriptTimeout: TimeInterval = 25
    static let launchTimeout: TimeInterval = 20
    static let updateWindowTimeout: TimeInterval = 30
    static let pollInterval: TimeInterval = 0.3
    static let settleSeconds: TimeInterval = 3
    static let feedOverrideKey = "LOCALPLAYER_TEST_FEED_URL"
    static let fixtureHost = "127.0.0.1"
    static let throwawayKeyBytes = 32
    static let installedVersion = "1.0"
    static let newerVersion = "2.0"
    static let dummySignatureBytes = 64
    static let updateWindowTitle = "Software Update"
    static let sampleStride = 8
    /// The mean brightness of a dark window must be below the light one's by at least this much (0...1 scale).
    static let minimumBrightnessGap = 0.15
    static let appMenuItemTitle = "Check for Updates…"

    var appURL: URL { Fixtures.directory.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/e2e-app/PlayawayE2E.app") }
    let dir = TempDir("e2egap")
    var server: Process?
    var patchedApp: URL?

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment[Self.approvalKey] == Self.approvedValue,
                          "needs owner permission to put windows on screen: set \(Self.approvalKey)=1")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: appURL.path), "dev bundle not built: run scripts/run-e2e.sh")
        continueAfterFailure = false
        killApp()
        _ = sh("/usr/bin/defaults", ["delete", Self.bundleID])
        clearSavedWindowState()
        _ = sh("/usr/bin/defaults", ["write", Self.bundleID, volumeSettingKey, "-float", "0"])
        _ = sh("/usr/bin/defaults", ["write", Self.bundleID, muteSettingKey, "-bool", "true"])
    }

    override func tearDown() {
        server?.terminate()
        server?.waitUntilExit()
        server = nil
        if FileManager.default.fileExists(atPath: appURL.path) {
            killApp()
            _ = sh("/usr/bin/defaults", ["delete", Self.bundleID])
            clearSavedWindowState()
        }
    }

    // MARK: helpers (same behaviour as E2ETests)

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

    func clearSavedWindowState() {
        let saved = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Saved Application State/\(Self.bundleID).savedState")
        try? FileManager.default.removeItem(at: saved)
    }

    /// The bundle under test: the patched copy when one was made, otherwise the dev bundle.
    var runningApp: URL { patchedApp ?? appURL }

    func launch(environment: [String: String] = [:]) throws {
        var args = ["-n", "-g"]
        for (key, value) in environment.sorted(by: { $0.key < $1.key }) { args += ["--env", "\(key)=\(value)"] }
        args += [runningApp.path, "--args", "-ApplePersistenceIgnoreState", "YES"]
        let result = sh("/usr/bin/open", args)
        XCTAssertEqual(result.status, 0, result.err)
        try waitForApp()
    }

    func waitForApp() throws {
        let deadline = Date().addingTimeInterval(Self.launchTimeout)
        while Date() < deadline {
            if sh("/usr/bin/pgrep", ["-x", Self.processName]).status == 0, osa("get volume").status == 0,
               !osa("get name of every playlist document").out.isEmpty { return }
            Thread.sleep(forTimeInterval: Self.pollInterval)
        }
        XCTFail("app did not become scriptable in time")
    }

    func osa(_ statement: String, timeout: TimeInterval = scriptTimeout) -> (status: Int32, out: String, err: String) {
        sh("/usr/bin/osascript", ["-e", "tell application \"\(runningApp.path)\"", "-e", statement, "-e", "end tell"], timeout: timeout)
    }

    func ax(_ body: String, timeout: TimeInterval = 60) -> (status: Int32, out: String, err: String) {
        sh("/usr/bin/osascript", ["-e", "tell application \"System Events\" to tell process \"\(Self.processName)\"", "-e", body, "-e", "end tell"], timeout: timeout)
    }

    func pid() -> String { sh("/usr/bin/pgrep", ["-x", Self.processName]).out }

    // MARK: 9.25 fixture: patched bundle copy, local feed server

    /// A copy of the dev bundle whose Info.plist passes the updater's own validation, ad-hoc signed, in a temp folder.
    func makePatchedApp() throws {
        let key = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        let copy = dir.url.appendingPathComponent("patched").appendingPathComponent("PlayawayE2E.app")
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: appURL, to: copy)
        let plist = copy.appendingPathComponent("Contents/Info.plist").path
        let edits = ["Set :SUFeedURL https://fixture.example.test/appcast.xml", "Set :SUPublicEDKey \(key)",
                     "Add :NSAppTransportSecurity dict", "Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true"]
        for edit in edits {
            let result = sh("/usr/libexec/PlistBuddy", ["-c", edit, plist])
            XCTAssertEqual(result.status, 0, "\(edit): \(result.err)")
        }
        XCTAssertEqual(sh("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", copy.path]).status, 0)
        patchedApp = copy
    }

    private func appcast(version: String) -> String {
        let signature = Data(count: Self.dummySignatureBytes).base64EncodedString()
        return """
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><title>Fixture</title>
        <item><title>Fixture \(version)</title><sparkle:version>\(version)</sparkle:version>
        <sparkle:shortVersionString>\(version)</sparkle:shortVersionString>
        <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
        <enclosure url="http://\(Self.fixtureHost)/Fixture-\(version).dmg" length="0" type="application/octet-stream" sparkle:edSignature="\(signature)"/>
        </item></channel></rss>
        """
    }

    /// Serves an appcast for `version` on a free local port and returns its address. The enclosure points nowhere
    /// real, so even a chosen install could not download anything.
    func serveFeed(version: String) throws -> String {
        let site = dir.url.appendingPathComponent("site-\(version)")
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        try appcast(version: version).write(to: site.appendingPathComponent("appcast.xml"), atomically: true, encoding: .utf8)
        let port = try freeLocalPort()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "http.server", "\(port)", "--bind", Self.fixtureHost, "--directory", site.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        server = process
        let feed = "http://\(Self.fixtureHost):\(port)/appcast.xml"
        let deadline = Date().addingTimeInterval(Self.launchTimeout)
        while Date() < deadline {
            if sh("/usr/bin/curl", ["-sf", "-o", "/dev/null", feed], timeout: 5).status == 0 { return feed }
            Thread.sleep(forTimeInterval: Self.pollInterval)
        }
        throw XCTSkip("fixture feed server did not start")
    }

    private func freeLocalPort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr(Self.fixtureHost)
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { throw XCTSkip("could not reserve a local port") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { throw XCTSkip("could not read the reserved port") }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    /// One line per window of the app: its title, its static texts and its button names. Playlist windows are in the
    /// baseline, so only what a route adds is compared.
    func windowSignatures() -> [String] {
        let script = """
        set out to ""
        repeat with w in windows
          set line_ to "window"
          try
            set line_ to line_ & "[" & (name of w) & "]"
          end try
          try
            repeat with e in (entire contents of w)
              try
                if role of e is "AXStaticText" then set line_ to line_ & "|" & (value of e)
              end try
              try
                if role of e is "AXButton" then set line_ to line_ & "|button:" & (name of e)
              end try
            end repeat
          end try
          set out to out & line_ & linefeed
        end repeat
        return out
        """
        return ax(script).out.split(whereSeparator: \.isNewline).map(String.init).sorted()
    }

    /// Waits for the updater to put something new on screen, then lets it settle.
    func newWindows(since baseline: [String]) -> [String] {
        let deadline = Date().addingTimeInterval(Self.updateWindowTimeout)
        var latest: [String] = []
        while Date() < deadline {
            latest = windowSignatures().filter { !baseline.contains($0) }
            // A window can exist for a moment before its texts and buttons are exposed: wait for some content.
            if latest.contains(where: { $0.contains("|") }) {
                Thread.sleep(forTimeInterval: Self.settleSeconds)
                return windowSignatures().filter { !baseline.contains($0) }
            }
            Thread.sleep(forTimeInterval: Self.pollInterval)
        }
        return latest
    }

    enum Route { case script, menu }

    /// A fresh launch against `feed`, one Check for Updates by `route`, and what appeared. The bundle's executable and
    /// Info.plist are hashed before and after, and no installer process may exist: nothing is installed.
    func checkForUpdates(by route: Route, feed: String) throws -> [String] {
        killApp()
        _ = sh("/usr/bin/defaults", ["delete", Self.bundleID])
        // A scheduled check at launch would put an unrelated window on screen; say one has just happened.
        _ = sh("/usr/bin/defaults", ["write", Self.bundleID, "SULastCheckTime", "-date", ISO8601DateFormatter().string(from: Date())])
        try launch(environment: [Self.feedOverrideKey: feed])
        let hashBefore = installedFilesDigest()
        let pidBefore = pid()
        _ = ax("set frontmost to true")
        let baseline = windowSignatures()
        switch route {
        case .script:
            let result = osa("check for updates")
            XCTAssertEqual(result.status, 0, "check for updates must be accepted (updater started): \(result.err)")
        case .menu:
            let click = ax("click menu item \"\(Self.appMenuItemTitle)\" of menu 1 of menu bar item \"\(Self.processName)\" of menu bar 1")
            XCTAssertEqual(click.status, 0, "the menu item must exist and be enabled: \(click.err)")
        }
        let appeared = newWindows(since: baseline)
        XCTAssertEqual(pid(), pidBefore, "the app was not replaced or restarted")
        XCTAssertEqual(installedFilesDigest(), hashBefore, "nothing was installed")
        XCTAssertNotEqual(sh("/usr/bin/pgrep", ["-f", "Autoupdate"]).status, 0, "no installer process was started")
        return appeared
    }

    func installedFilesDigest() -> String {
        let files = ["Contents/MacOS/\(Self.processName)", "Contents/Info.plist"].map { runningApp.appendingPathComponent($0).path }
        return files.map { sh("/usr/bin/shasum", ["-a", "256", $0]).out.split(separator: " ").first.map(String.init) ?? "" }.joined(separator: ",")
    }

    // MARK: Task 9.25 -- TC-35 and E2E-6

    /// Body: "osascript check for updates against a local fixture feed. Assert the same update window or up-to-date
    /// message appears by both routes and nothing is installed without choosing." (feed at the installed version)
    func testCheckForUpdatesByScriptAndMenuShowTheSameUpToDateMessage() throws {
        try makePatchedApp()
        let feed = try serveFeed(version: Self.installedVersion)
        let byScript = try checkForUpdates(by: .script, feed: feed)
        let byMenu = try checkForUpdates(by: .menu, feed: feed)
        XCTAssertFalse(byScript.isEmpty, "the script route shows an up-to-date message")
        XCTAssertFalse(byMenu.isEmpty, "the menu route shows an up-to-date message")
        XCTAssertEqual(byScript, byMenu, "both routes show the same thing")
        // System Events does not expose Sparkle's alert text (a first run showed the window with no readable text), so
        // the up-to-date outcome is asserted as "an untitled alert window appears and it is not the update window".
        XCTAssertFalse(byScript.joined(separator: "\n").contains(Self.updateWindowTitle), "no update window is offered: \(byScript)")
    }

    /// The same comparison when the feed offers a newer version: the same update window by both routes, with the
    /// install left unchosen (the digests and the process id are asserted unchanged inside checkForUpdates).
    func testCheckForUpdatesByScriptAndMenuShowTheSameUpdateWindow() throws {
        try makePatchedApp()
        let feed = try serveFeed(version: Self.newerVersion)
        let byScript = try checkForUpdates(by: .script, feed: feed)
        let byMenu = try checkForUpdates(by: .menu, feed: feed)
        XCTAssertFalse(byScript.isEmpty, "the script route shows the update window")
        XCTAssertEqual(byScript, byMenu, "both routes show the same update window")
        // Sparkle's update window is titled "Software Update"; its body text is not readable through System Events.
        XCTAssertTrue(byScript.joined(separator: "\n").contains(Self.updateWindowTitle), "the update window is shown: \(byScript)")
    }

    // MARK: Task 8.11 -- appearance and accessibility settings

    /// The accessibility display settings as the system reports them. Reading only.
    struct AccessibilitySettings: Equatable {
        let increaseContrast: Bool, reduceTransparency: Bool, reduceMotion: Bool

        static func read() -> AccessibilitySettings {
            let workspace = NSWorkspace.shared
            return AccessibilitySettings(increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
                                         reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                                         reduceMotion: workspace.accessibilityDisplayShouldReduceMotion)
        }
    }

    /// The raw stored values of the same settings, read with `defaults` (never written).
    func storedAccessibilityValues() -> [String] {
        ["reduceTransparency", "increaseContrast", "reduceMotion"].map {
            sh("/usr/bin/defaults", ["read", "com.apple.universalaccess", $0]).out
        }
    }

    func systemIsDark() -> Bool {
        sh("/usr/bin/osascript", ["-e", "tell application \"System Events\" to tell appearance preferences to get dark mode"]).out == "true"
    }

    @discardableResult
    func setSystemDark(_ dark: Bool) -> Bool {
        sh("/usr/bin/osascript", ["-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"]).status == 0
    }

    /// Mean brightness (0 dark ... 1 light) of the app's largest on-screen window, captured with screencapture.
    func windowBrightness() throws -> Double {
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let ours = windows.filter { ($0[kCGWindowOwnerName as String] as? String) == Self.processName && ($0[kCGWindowLayer as String] as? Int) == 0 }
        func area(_ info: [String: Any]) -> CGFloat {
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return 0 }
            return (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
        }
        let target = try XCTUnwrap(ours.max { area($0) < area($1) }, "no on-screen window of the app")
        let id = try XCTUnwrap(target[kCGWindowNumber as String] as? Int)
        let png = dir.path("window-\(UUID().uuidString).png")
        let capture = sh("/usr/sbin/screencapture", ["-x", "-o", "-l", "\(id)", png.path])
        XCTAssertEqual(capture.status, 0, "screencapture needs Screen Recording permission for the terminal: \(capture.err)")
        let image = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: png)), "unreadable capture")
        var total = 0.0, count = 0.0
        for y in stride(from: 0, to: image.pixelsHigh, by: Self.sampleStride) {
            for x in stride(from: 0, to: image.pixelsWide, by: Self.sampleStride) {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                total += Double(color.brightnessComponent); count += 1
            }
        }
        return count == 0 ? 0 : total / count
    }

    /// E2E-2 (TC-21, TC-24, TC-75, TC-09): switch the real system appearance light to dark and back with a playlist
    /// window open, asserting before and after and that the same process keeps running (no restart). The original
    /// appearance is restored in a defer and in a teardown block, even when an assertion fails. User accessibility
    /// settings are only read, before and after; nothing here writes them.
    func testRealSystemAppearanceSwitchIsFollowedLiveWithoutRestart() throws {
        let original = systemIsDark()
        let accessibilityBefore = AccessibilitySettings.read()
        let storedBefore = storedAccessibilityValues()
        addTeardownBlock { [self] in if systemIsDark() != original { setSystemDark(original) } }
        defer { if systemIsDark() != original { setSystemDark(original) } }

        XCTAssertTrue(setSystemDark(false), "switch to light")
        try launch()
        XCTAssertEqual(osa("add track \"\(dir.copyFixture("long30.mp3").path)\" to \"Untitled\"").status, 0)
        let runningPid = pid()
        Thread.sleep(forTimeInterval: Self.settleSeconds)
        let light = try windowBrightness()

        XCTAssertTrue(setSystemDark(true), "switch to dark")           // TC-21, TC-09
        Thread.sleep(forTimeInterval: Self.settleSeconds)
        let dark = try windowBrightness()
        XCTAssertEqual(pid(), runningPid, "TC-75: no restart")
        XCTAssertLessThan(dark, light - Self.minimumBrightnessGap, "the open window became dark (light \(light), dark \(dark))")

        XCTAssertTrue(setSystemDark(false), "switch back to light")    // TC-24
        Thread.sleep(forTimeInterval: Self.settleSeconds)
        let lightAgain = try windowBrightness()
        XCTAssertEqual(pid(), runningPid, "TC-75: no restart")
        XCTAssertGreaterThan(lightAgain, dark + Self.minimumBrightnessGap, "the open window became light again")

        XCTAssertTrue(setSystemDark(original))
        XCTAssertEqual(systemIsDark(), original, "original appearance restored")
        XCTAssertEqual(AccessibilitySettings.read(), accessibilityBefore, "accessibility settings were not changed")
        XCTAssertEqual(storedAccessibilityValues(), storedBefore, "stored accessibility values were not changed")
    }

    /// E2E-3, TC-70, TC-13: launch, use, quit; the system's Reduce Transparency (and Increase Contrast, Reduce Motion)
    /// are unchanged. This test never turns a setting on: it reads whatever state the person has. TC-13 (dark with
    /// Reduce Transparency on) is exercised only when the person has Reduce Transparency enabled for the run, and the
    /// run records which state it saw. The appearance is not switched here.
    func testAccessibilitySettingsAreOnlyReadAcrossLaunchAndQuit() throws {
        let before = AccessibilitySettings.read()
        let storedBefore = storedAccessibilityValues()
        XCTContext.runActivity(named: "Accessibility state at start: \(before)") { _ in }
        try launch()
        XCTAssertEqual(osa("get name of every playlist document").status, 0, "renders and responds under this setting")
        _ = osa("quit")
        let deadline = Date().addingTimeInterval(Self.launchTimeout)
        while sh("/usr/bin/pgrep", ["-x", Self.processName]).status == 0 && Date() < deadline { Thread.sleep(forTimeInterval: Self.pollInterval) }
        XCTAssertNotEqual(sh("/usr/bin/pgrep", ["-x", Self.processName]).status, 0, "the app quit")
        XCTAssertEqual(AccessibilitySettings.read(), before, "TC-70: the app did not change an accessibility setting")
        XCTAssertEqual(storedAccessibilityValues(), storedBefore, "TC-70: stored values are identical")
    }

    /// Proposed E2E-4: every button, slider and checkbox in a playlist window exposes a name or description to
    /// assistive technology. Known exceptions are recorded in `knownUnlabelled` (none are known yet).
    func testPlaylistWindowControlsAreLabelledForAccessibility() throws {
        let knownUnlabelled: Set<String> = []
        try launch()
        XCTAssertEqual(osa("add track \"\(dir.copyFixture("long30.mp3").path)\" to \"Untitled\"").status, 0)
        let script = """
        set out to ""
        repeat with e in (entire contents of window 1)
          try
            set r to role of e
            if r is in {"AXButton", "AXSlider", "AXCheckBox"} then
              set label_ to ""
              try
                set label_ to (description of e)
              end try
              if label_ is "" or label_ is "missing value" then
                try
                  set label_ to (name of e)
                end try
              end if
              if label_ is "" or label_ is "missing value" then set out to out & r & linefeed
            end if
          end try
        end repeat
        return out
        """
        let unlabelled = Set(ax(script).out.split(whereSeparator: \.isNewline).map(String.init))
        XCTAssertEqual(unlabelled.subtracting(knownUnlabelled), [], "controls without a name or description")
    }
}
