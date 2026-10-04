import XCTest
import AppKit
@testable import LocalPlayer

let bundledManifestURL = Fixtures.directory.deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/ui-manifest.json")

final class UIManifestUnitTests: XCTestCase {
    func manifest(_ json: String) throws -> UIManifest { try UIManifest(data: Data(json.utf8)) }

    func testResourceMissingOrEmpty() {                                              // TC-20
        XCTAssertThrowsError(try UIManifest(data: Data())) { XCTAssertEqual($0 as? ManifestError, .emptyFile) }
        XCTAssertThrowsError(try UIManifest.load(overridePath: "/nonexistent/ui-manifest.json")) { XCTAssertEqual($0 as? ManifestError, .emptyFile) }
    }

    func testValidShapes() throws {                                                   // TC-21/22/27/34
        XCTAssertEqual(try manifest(#"{"windows":{"playlist":[]}}"#).entries[.playlist]?.count, 0)
        XCTAssertEqual(try manifest(#"{"windows":{"playlist":[{"element":"a","job":"play_file"}]}}"#).entries[.playlist]?.count, 1)
        for job in Job.allCases {
            XCTAssertNoThrow(try manifest(#"{"windows":{"playlist":[{"element":"a","job":"\#(job.rawValue)"}]}}"#))
        }
        XCTAssertNoThrow(try manifest(#"{"windows":{"playlist":[{"element":"playback.volume","job":"play_file"},{"element":"playback.mute","job":"play_file"}]}}"#))
    }

    func testInvalidShapes() {
        XCTAssertThrowsError(try manifest("not json")) { XCTAssertEqual($0 as? ManifestError, .malformed) }              // TC-23
        XCTAssertThrowsError(try manifest(#"{"windows":{"playlist":[{"element":" ","job":"play_file"}]}}"#)) {          // TC-24
            XCTAssertEqual($0 as? ManifestError, .blankElementID(0)) }
        XCTAssertThrowsError(try manifest(#"{"windows":{"playlist":[{"element":"a","job":"play_file"},{"element":"a","job":"play_file"}]}}"#)) {
            XCTAssertEqual($0 as? ManifestError, .duplicateElementID("a")) }                                              // TC-25
        XCTAssertThrowsError(try manifest(#"{"windows":{"playlist":[{"element":"a","job":"decorate"}]}}"#)) {
            XCTAssertEqual($0 as? ManifestError, .unknownJob("decorate")) }                                               // TC-26
        XCTAssertThrowsError(try manifest(#"{"windows":{"mainwindow":[]}}"#)) {
            XCTAssertEqual($0 as? ManifestError, .unknownWindowKind("mainwindow")) }                                      // TC-36
    }

    func entry(_ id: String, _ job: Job = .playFile) -> ManifestEntry { ManifestEntry(elementID: id, job: job) }
    func el(_ id: String?, _ role: String = "AXButton") -> ObservedElement { ObservedElement(id: id, role: role) }

    func testCheckerAgreeUnrecordedStaleUnidentified() {
        let man = UIManifest(entries: [.playlist: [entry("a"), entry("b")]])
        let agree = ManifestChecker.check(manifest: man, kind: .playlist, observed: [.idle: [el("a"), el("b")]])
        XCTAssertTrue(agree.isEmpty)
        for state in WindowState.allCases {
            var observed: [WindowState: [ObservedElement]] = [.idle: [el("a"), el("b")]]
            observed[state, default: []].append(el("extra"))
            XCTAssertEqual(ManifestChecker.check(manifest: man, kind: .playlist, observed: observed), [.unrecorded("extra", state)], "R2 \(state)")
            var unnamed: [WindowState: [ObservedElement]] = [.idle: [el("a"), el("b")]]
            unnamed[state, default: []].append(el(nil, "AXSlider"))
            XCTAssertEqual(ManifestChecker.check(manifest: man, kind: .playlist, observed: unnamed), [.unidentified("AXSlider", state)], "R4 \(state)")
            XCTAssertEqual(ManifestChecker.check(manifest: man, kind: .playlist, observed: [state: [el("a")]]), [.stale("b")], "R3 \(state)")
        }
    }

    func testStaleMeansAbsentFromEveryState() {                                       // TC-28
        let man = UIManifest(entries: [.playlist: [entry("pause")]])
        XCTAssertTrue(ManifestChecker.check(manifest: man, kind: .playlist, observed: [.playing: [el("pause")], .idle: []]).isEmpty)
    }

    func testAllViolationsReportedTogetherAndEmptyPasses() {                          // TC-29 / TC-30
        let man = UIManifest(entries: [.playlist: [entry("gone")]])
        let result = ManifestChecker.check(manifest: man, kind: .playlist, observed: [.idle: [el("x"), el(nil)]])
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(ManifestChecker.check(manifest: UIManifest(entries: [.playlist: []]), kind: .playlist, observed: [:]).isEmpty)
    }

    func testViolationMessagesNameTheElement() {
        XCTAssertTrue(Violation.unrecorded("playback.confetti", .playing).description.contains("playback.confetti"))
        XCTAssertTrue(Violation.stale("old").description.contains("old"))
    }

    func testBundledManifestIsValidAndUsesOnlyTheThreeJobs() throws {
        let manifest = try UIManifest(data: Data(contentsOf: bundledManifestURL))
        let entries = manifest.entries[.playlist] ?? []
        XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(Set(entries.map(\.job)), Set(Job.allCases))
        XCTAssertTrue(entries.contains(ManifestEntry(elementID: "playback.volume", job: .playFile)))
        XCTAssertTrue(entries.contains(ManifestEntry(elementID: "playback.mute", job: .playFile)))
    }
}

/// The real window, in each state, against the real bundled manifest.
@MainActor
final class UIManifestIntegrationTests: XCTestCase {
    var app: TestApp!
    var keep: [URL] = []
    let audio = TempDir("uicheck")

    override func setUp() async throws {
        app = TestApp()
        keep = ["track1.mp3", "tone.wav", "tone.m4a"].map { audio.copyFixture($0) }
    }
    override func tearDown() async throws { app.tearDown() }

    func manifest() throws -> UIManifest { try UIManifest(data: Data(contentsOf: bundledManifestURL)) }

    func dumpAll(inject: NSView? = nil) throws -> [WindowState: [ObservedElement]] {
        var observed: [WindowState: [ObservedElement]] = [:]
        for state in WindowState.allCases {
            let check = try UICheckMode(fixtureAudio: keep)
            check.injectedView = inject
            observed[state] = try check.visibleElements(in: state)
        }
        return observed
    }

    func testRealAppAndRecordAgreeInEveryState() throws {                             // TC-01..04, 100, E2E-1 (in process)
        let observed = try dumpAll()
        let violations = ManifestChecker.check(manifest: try manifest(), kind: .playlist, observed: observed)
        XCTAssertTrue(violations.isEmpty, violations.map(\.description).joined(separator: "\n"))
        for state in WindowState.allCases { XCTAssertFalse(observed[state]!.isEmpty, "\(state)") }
    }

    func testPlayingStateShowsVolumeAndMuteWithRoles() throws {                       // TC-35
        let elements = try UICheckMode(fixtureAudio: keep).visibleElements(in: .playing)
        XCTAssertEqual(elements.first { $0.id == "playback.volume" }?.role, "AXSlider")
        XCTAssertNotNil(elements.first { $0.id == "playback.mute" })
    }

    func testEmptyHintShowsOnlyWhenThePlaylistIsEmpty() throws {
        let empty = try UICheckMode(fixtureAudio: keep).visibleElements(in: .untitledEmpty).compactMap(\.id)
        XCTAssertTrue(empty.contains("playlist.empty"))
        let idle = try UICheckMode(fixtureAudio: keep).visibleElements(in: .idle).compactMap(\.id)
        XCTAssertFalse(idle.contains("playlist.empty"))
    }

    func testAnExtraUnrecordedElementIsCaughtAndNamed() throws {                      // TC-05..08, E2E-2
        let extra = NSButton(title: "Upgrade", target: nil, action: nil)
        extra.setAccessibilityIdentifier("promo.upgrade")
        let violations = ManifestChecker.check(manifest: try manifest(), kind: .playlist, observed: try dumpAll(inject: extra))
        XCTAssertEqual(Set(violations.map(\.description)).count, violations.count)
        XCTAssertTrue(violations.contains(.unrecorded("promo.upgrade", .idle)))
        XCTAssertTrue(violations.allSatisfy { if case .unrecorded("promo.upgrade", _) = $0 { return true } else { return false } })
    }

    func testAnUnnamedViewIsReportedAsUnidentified() throws {                         // TC-13..16
        let unnamed = NSButton(title: "Mystery", target: nil, action: nil)
        let violations = ManifestChecker.check(manifest: try manifest(), kind: .playlist, observed: try dumpAll(inject: unnamed))
        XCTAssertTrue(violations.contains(.unidentified("AXButton", .playing)))
    }

    func testRemovingARecordFailsNamingTheElement() throws {                          // TC-09..12, E2E-3
        let full = try manifest()
        let trimmed = UIManifest(entries: [.playlist: full.entries[.playlist]!.filter { $0.elementID != "playback.next" }])
        let violations = ManifestChecker.check(manifest: trimmed, kind: .playlist, observed: try dumpAll())
        XCTAssertTrue(violations.contains(.unrecorded("playback.next", .idle)))
    }

    func testMissingRecordedElementIsStale() throws {
        let full = try manifest()
        var entries = full.entries[.playlist]!
        entries.append(ManifestEntry(elementID: "playback.equalizer", job: .playFile))
        let violations = ManifestChecker.check(manifest: UIManifest(entries: [.playlist: entries]), kind: .playlist, observed: try dumpAll())
        XCTAssertEqual(violations, [.stale("playback.equalizer")])
    }

    func testEnumeratorIsStableAndChangesNothing() throws {                           // TC-33 / TC-42
        let first = try UICheckMode(fixtureAudio: keep).visibleElements(in: .idle)
        let second = try UICheckMode(fixtureAudio: keep).visibleElements(in: .idle)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, first.sorted { ($0.id ?? "", $0.role) < ($1.id ?? "", $1.role) })
    }

    func testHiddenViewsAreNotVisibleElements() throws {                              // TC-32
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let root = NSStackView()
        let shown = NSButton(title: "shown", target: nil, action: nil); shown.setAccessibilityIdentifier("shown")
        let hidden = NSButton(title: "hidden", target: nil, action: nil); hidden.setAccessibilityIdentifier("hidden"); hidden.isHidden = true
        root.addArrangedSubview(shown); root.addArrangedSubview(hidden)
        window.contentView = root
        XCTAssertEqual(WindowElementWalker.elements(in: window).compactMap(\.id), ["shown"])
    }

    func testNoMainWindowOrPlaylistListExists() throws {                              // TC-46
        _ = try UICheckMode(fixtureAudio: keep).visibleElements(in: .idle)
        let others = NSApp.windows.filter { $0.isVisible && !($0.windowController is PlaylistWindowController) && $0.styleMask.contains(.titled) }
        XCTAssertTrue(others.isEmpty, others.map { "\(type(of: $0)) '\($0.title)'" }.joined(separator: ", "))
    }

    func testDumpLeavesNoFixtureInUserFolders() throws {                              // TC-45
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let before = (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []
        _ = try UICheckMode(fixtureAudio: keep).visibleElements(in: .playing)
        XCTAssertEqual(before, (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? [])
    }

    func testUnknownStateAndKindAreErrors() {                                         // TC-31
        XCTAssertThrowsError(try UICheckMode(fixtureAudio: keep).dump(kind: "playlist", state: "dancing")) {
            XCTAssertEqual($0 as? EnumerationError, .stateUnavailable("dancing")) }
        XCTAssertThrowsError(try UICheckMode(fixtureAudio: keep).dump(kind: "main", state: "idle"))
    }
}

/// The built executable, launched with the real flag (E2E-1, TC-44).
final class UIManifestLaunchModeTests: XCTestCase {
    var executable: URL { Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("LocalPlayer") }

    func runDump(_ state: String) throws -> (status: Int32, elements: [ObservedElement]) {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--dump-window-elements", "playlist", state] + ["track1.mp3", "tone.wav", "tone.m4a"].map { Fixtures.url($0).path }
        let out = Pipe()
        process.environment = ["DYLD_FRAMEWORK_PATH": executable.deletingLastPathComponent().path]   // the bare binary has no rpath to Sparkle
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let elements = (try? JSONDecoder().decode([ObservedElement].self, from: data)) ?? []
        return (process.terminationStatus, elements)
    }

    func testBuiltAppDumpsEveryStateAndTheCheckPasses() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: executable.path), "built executable not found")
        let manifest = try UIManifest(data: Data(contentsOf: bundledManifestURL))
        var observed: [WindowState: [ObservedElement]] = [:]
        for state in WindowState.allCases {
            let run = try runDump(state.rawValue)
            XCTAssertEqual(run.status, 0, "\(state)")
            observed[state] = run.elements
        }
        let violations = ManifestChecker.check(manifest: manifest, kind: .playlist, observed: observed)
        XCTAssertTrue(violations.isEmpty, violations.map(\.description).joined(separator: "\n"))
    }

    func testUnreachableStateExitsNonZero() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: executable.path), "built executable not found")
        XCTAssertNotEqual(try runDump("dancing").status, 0)
    }
}
