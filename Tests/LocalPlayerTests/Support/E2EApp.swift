import AppKit
import XCTest
@testable import LocalPlayer
@testable import PlayawayCore

/// Drives the built, ad-hoc signed e2e bundle from outside, the way E2ETests does: `open` with environment
/// variables, `osascript` against the app, System Events against its windows, `screencapture` for what only pixels
/// can tell. Audio is silenced before anything plays. Nothing reaches the person's own data: the bundle has its own
/// identifier and defaults, and iCloud is a stand-in folder in a temp directory (`CloudStandIn`).
final class E2EApp {
    static let bundleID = E2ETests.bundleID
    static let processName = E2ETests.processName
    static let scriptTimeout: TimeInterval = 25
    static let launchTimeout: TimeInterval = 20
    static let axTimeout: TimeInterval = 60
    static let pollInterval: TimeInterval = 0.3
    static let quitTimeout: TimeInterval = 10

    let appURL: URL = Fixtures.directory.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/e2e-app/PlayawayE2E.app")

    var isBuilt: Bool { FileManager.default.fileExists(atPath: appURL.path) }

    /// System Events reports no windows for any app while the session's screen is locked.
    static var isScreenLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    /// Kills any earlier copy and starts from empty defaults, silent.
    func reset() {
        killApp()
        _ = sh("/usr/bin/defaults", ["delete", Self.bundleID])
        clearSavedWindowState()
        _ = sh("/usr/bin/defaults", ["write", Self.bundleID, volumeSettingKey, "-float", "0"])
        _ = sh("/usr/bin/defaults", ["write", Self.bundleID, muteSettingKey, "-bool", "true"])
    }

    func tearDown() {
        killApp()
        _ = sh("/usr/bin/defaults", ["delete", Self.bundleID])
        clearSavedWindowState()
    }

    func clearSavedWindowState() {
        let saved = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Saved Application State/\(Self.bundleID).savedState")
        try? FileManager.default.removeItem(at: saved)
    }

    // MARK: processes

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
        while isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    }

    var isRunning: Bool { sh("/usr/bin/pgrep", ["-x", Self.processName]).status == 0 }

    /// Launches the app with the given environment (the iCloud stand-in goes here) and waits until it is scriptable.
    func launch(environment: [String: String] = [:], opening files: [URL] = []) throws {
        var args = ["-n", "-g"]
        for (key, value) in environment { args += ["--env", "\(key)=\(value)"] }
        args += [appURL.path, "--args", "-ApplePersistenceIgnoreState", "YES"]
        let result = sh("/usr/bin/open", args)
        XCTAssertEqual(result.status, 0, result.err)
        if !files.isEmpty { _ = sh("/usr/bin/open", ["-g", "-a", appURL.path] + files.map(\.path)) }
        try waitForApp()
    }

    func open(_ file: URL) { _ = sh("/usr/bin/open", ["-g", "-a", appURL.path, file.path]) }

    func waitForApp() throws {
        let deadline = Date().addingTimeInterval(Self.launchTimeout)
        while Date() < deadline {
            if isRunning, osa("get volume").status == 0, !osa("get name of every playlist document").out.isEmpty { return }
            Thread.sleep(forTimeInterval: Self.pollInterval)
        }
        XCTFail("app did not become scriptable in time")
    }

    func quit() {
        _ = osa("quit")
        let deadline = Date().addingTimeInterval(Self.quitTimeout)
        while isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
    }

    // MARK: scripting

    func osa(_ statement: String, timeout: TimeInterval = scriptTimeout) -> (status: Int32, out: String, err: String) {
        sh("/usr/bin/osascript", ["-e", "tell application \"\(appURL.path)\"", "-e", statement, "-e", "end tell"], timeout: timeout)
    }

    /// Runs a statement expected to fail and returns the error number and message.
    func osaError(_ statement: String, timeout: TimeInterval = scriptTimeout) -> (number: Int, message: String)? {
        let result = sh("/usr/bin/osascript", ["-e", "tell application \"\(appURL.path)\"", "-e", "try", "-e", statement, "-e", "return \"ok\"",
                                               "-e", "on error msg number n", "-e", "return \"error \" & n & \": \" & msg", "-e", "end try", "-e", "end tell"], timeout: timeout)
        guard result.out.hasPrefix("error ") else { return nil }
        let rest = result.out.dropFirst(6)
        guard let number = Int(rest.prefix(while: { $0.isNumber })) else { return nil }
        let message = rest.drop(while: { $0 != ":" }).dropFirst(2)
        return (number, String(message))
    }

    /// Starts a statement without waiting for it (a scripted play that downloads first); the result arrives later.
    func osaInBackground(_ statement: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"\(appURL.path)\"", "-e", statement, "-e", "end tell"]
        process.standardOutput = Pipe(); process.standardError = Pipe()
        try? process.run()
        return process
    }

    func waitFor(_ statement: String, equals expected: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if osa(statement).out == expected { return true }
            Thread.sleep(forTimeInterval: Self.pollInterval)
        }
        return false
    }

    func wait(timeout: TimeInterval = 10, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: Self.pollInterval)
        }
        return condition()
    }

    // MARK: the real window, through System Events

    func ax(_ body: String, timeout: TimeInterval = axTimeout) -> (status: Int32, out: String, err: String) {
        sh("/usr/bin/osascript", ["-e", "tell application \"System Events\" to tell process \"\(Self.processName)\"", "-e", body, "-e", "end tell"], timeout: timeout)
    }

    /// One AppleScript-quoted string.
    static func quoted(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }

    /// The elements of a window that carry the identifier, in walk order: each as description, value, position, size.
    struct Element: Equatable {
        var description: String
        var value: String
        var position: CGPoint
        var size: CGSize
        var center: CGPoint { CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2) }
    }

    func elements(identifier: String, inWindow window: String) -> [Element] {
        let script = """
        set out to ""
        set els to entire contents of window \(Self.quoted(window))
        repeat with e in els
          try
            if (value of attribute "AXIdentifier" of e) is \(Self.quoted(identifier)) then
              set d to ""
              try
                set d to description of e
              end try
              set v to ""
              try
                set v to value of e as text
              end try
              set p to position of e
              set s to size of e
              set out to out & d & tab & v & tab & (item 1 of p) & tab & (item 2 of p) & tab & (item 1 of s) & tab & (item 2 of s) & linefeed
            end if
          end try
        end repeat
        return out
        """
        let result = ax(script)
        return result.out.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 6, let x = Double(parts[2]), let y = Double(parts[3]), let w = Double(parts[4]), let h = Double(parts[5]) else { return nil }
            return Element(description: parts[0], value: parts[1], position: CGPoint(x: x, y: y), size: CGSize(width: w, height: h))
        }
    }

    /// Clicks the n-th element (1-based) of the window carrying the identifier.
    @discardableResult
    func click(identifier: String, inWindow window: String, index: Int = 1) -> Bool {
        let script = """
        set n to 0
        set els to entire contents of window \(Self.quoted(window))
        repeat with e in els
          try
            if (value of attribute "AXIdentifier" of e) is \(Self.quoted(identifier)) then
              set n to n + 1
              if n is \(index) then
                click e
                return "clicked"
              end if
            end if
          end try
        end repeat
        return "not found"
        """
        return ax(script).out == "clicked"
    }

    /// The spoken labels of the song rows, in order (what VoiceOver reads: the name, then the state suffixes).
    func rowLabels(inWindow window: String) -> [String] {
        let script = """
        set out to ""
        set els to entire contents of window \(Self.quoted(window))
        repeat with e in els
          try
            if role of e is "AXRow" then
              set d to ""
              try
                set d to description of UI element 1 of e
              end try
              set out to out & d & linefeed
            end if
          end try
        end repeat
        return out
        """
        return ax(script).out.split(whereSeparator: \.isNewline).map(String.init)
    }

    /// The cloud icon labels of the song rows, in order (empty for an unsynced playlist).
    func cloudLabels(inWindow window: String) -> [String] {
        elements(identifier: ElementID.songCloud, inWindow: window).map(\.description)
    }

    // MARK: sheets

    /// The title (first static text) and button names of the sheet on the window, nil when there is none.
    func sheet(onWindow window: String) -> (title: String, message: String, buttons: [String])? {
        let script = """
        if not (exists sheet 1 of window \(Self.quoted(window))) then return "none"
        set texts to value of every static text of sheet 1 of window \(Self.quoted(window))
        set names to name of every button of sheet 1 of window \(Self.quoted(window))
        set AppleScript's text item delimiters to "|"
        return (texts as text) & linefeed & (names as text)
        """
        let result = ax(script)
        guard result.out != "none", !result.out.isEmpty else { return nil }
        let lines = result.out.components(separatedBy: "\n")
        let texts = lines.first?.components(separatedBy: "|") ?? []
        let buttons = lines.count > 1 ? lines[1].components(separatedBy: "|") : []
        return (texts.first ?? "", texts.dropFirst().first ?? "", buttons)
    }

    func waitForSheet(titled title: String, onWindow window: String, timeout: TimeInterval = 10) -> (title: String, message: String, buttons: [String])? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let sheet = sheet(onWindow: window), sheet.title == title { return sheet }
            Thread.sleep(forTimeInterval: Self.pollInterval)
        }
        return sheet(onWindow: window)
    }

    func clickSheetButton(_ name: String, onWindow window: String) -> Bool {
        ax("click button \(Self.quoted(name)) of sheet 1 of window \(Self.quoted(window))").status == 0
    }

    func waitForNoSheet(onWindow window: String, timeout: TimeInterval = 10) -> Bool {
        wait(timeout: timeout) { sheet(onWindow: window) == nil }
    }

    // MARK: pixels

    /// Captures a screen rectangle (top-left origin, the coordinates System Events reports) and returns how many of
    /// its pixels differ from its most common colour: zero means nothing is drawn there.
    func distinctPixels(in rect: CGRect, into dir: TempDir) -> Int {
        let png = dir.path("capture-\(UUID().uuidString).png")
        let region = "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
        let capture = sh("/usr/sbin/screencapture", ["-x", "-o", "-R", region, png.path])
        guard capture.status == 0, let image = NSImage(contentsOf: png), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return -1 }
        let width = cg.width, height = cg.height
        var pixels = [UInt32](repeating: 0, count: width * height)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var counts: [UInt32: Int] = [:]
        for pixel in pixels { counts[pixel, default: 0] += 1 }
        let commonest = counts.values.max() ?? 0
        return pixels.count - commonest
    }
}
