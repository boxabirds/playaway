import XCTest
import AppKit
@testable import LocalPlayer

/// Launch ordering with real documents: nothing about the audio files is touched before the first window is shown,
/// and when it is, the work runs off the main thread (launch.window.first_paint TC-38 / TC-40 / TC-56).
@MainActor
final class LaunchDocumentTests: XCTestCase {
    final class ThreadRecordingResolver: TrackResolving {
        let real = TrackResolver()
        private let lock = NSLock()
        private var calls: [Bool] = []
        func resolve(_ ref: TrackReference) -> (TrackStatus, TrackReference) {
            lock.lock(); calls.append(Thread.isMainThread); lock.unlock()
            return real.resolve(ref)
        }
        var mainThreadFlags: [Bool] { lock.lock(); defer { lock.unlock() }; return calls }
    }

    var saved = LaunchState.firstWindowPresented
    override func tearDown() async throws { LaunchState.firstWindowPresented = saved }

    func makeApp(resolver: TrackResolving) -> TestApp {
        let app = TestApp()
        let defaults = isolatedDefaults()
        let engine = AVPlaybackEngine(backend: app.backend, devices: StubOutputDevices(hasOutputDevice: true), settings: VolumeSettingsStore(defaults: defaults))
        AppServices.shared = AppServices(defaults: defaults, engine: engine, notices: app.notices, resolver: resolver, runsTimer: false)
        AppServices.shared.connect(controller: app.controller)
        return app
    }

    func testRestoredPlaylistIsNotResolvedUntilTheFirstWindowIsPresented() {
        let resolver = ThreadRecordingResolver()
        let app = makeApp(resolver: resolver)
        defer { app.tearDown() }
        LaunchState.firstWindowPresented = false
        let fixture = PlaylistFixture()
        fixture.deleteFile(at: 2)                                      // a missing file the first window must not wait for
        let folder = TempDir()
        let doc = app.openSaved(fixture.playlist, at: folder.path("L.lplaylist"))
        XCTAssertNotNil(doc.windowControllers.first?.window, "the window is up")
        spin(timeout: 0.4) { false }
        XCTAssertTrue(resolver.mainThreadFlags.isEmpty, "no audio file is looked at before the first window is presented")
        XCTAssertNil(doc.statuses.status(of: fixture.tracks[0].id))
        LaunchState.firstWindowPresented = true
        doc.firstWindowPresented()                                     // the observer's signal
        spin { doc.statuses.status(of: fixture.tracks[2].id) != nil }
        XCTAssertEqual(doc.statuses.status(of: fixture.tracks[2].id), .missing, "statuses are applied after the window is shown")
        XCTAssertEqual(resolver.mainThreadFlags.count, 5)
        XCTAssertFalse(resolver.mainThreadFlags.contains(true), "resolution runs off the main thread")
    }

    func testFirstWindowSignalIsDeliveredOnceAndOnlyAfterTheWindowIsPresentedWithRealDocuments() {
        final class Recorder: FirstWindowObserver { var calls = 0; func firstWindowPresented() { calls += 1 } }
        let app = makeApp(resolver: TrackResolver())
        defer { app.tearDown() }
        let recorder = Recorder()
        final class Windows: LaunchWindowProviding {
            var created = false
            var completion: (() -> Void)?
            func presentFirstWindow(completion: @escaping () -> Void) {
                _ = try? PlaylistDocumentController.current.openUntitledDocumentAndDisplay(true)
                created = true
                self.completion = completion
            }
        }
        let windows = Windows()
        let coordinator = LaunchCoordinator(trace: LaunchTrace(resultsPath: nil), observers: [recorder, DocumentResolutionObserver()], windows: windows)
        coordinator.start()
        XCTAssertTrue(windows.created)
        XCTAssertEqual(recorder.calls, 0, "not notified while the window is still being presented")
        windows.completion?()
        windows.completion?()
        XCTAssertEqual(recorder.calls, 1)
        XCTAssertEqual(coordinator.phase, .running)
        XCTAssertTrue(LaunchState.firstWindowPresented)
    }

    func testAnUnreadableRestoredPlaylistStillLeavesAWindow() {
        let app = makeApp(resolver: TrackResolver())
        defer { app.tearDown() }
        let dir = TempDir()
        let bad = dir.path("Bad.lplaylist"); try! Data("garbage".utf8).write(to: bad)
        var error: Error?, finished = false
        app.controller.openDocument(withContentsOf: bad, display: true) { _, _, e in error = e; finished = true }
        spin { finished }
        XCTAssertNotNil(error)
        XCTAssertTrue(app.controller.documents.isEmpty)
        let provider = DocumentLaunchWindows()
        var shown = false
        provider.presentFirstWindow { shown = true }
        spin { shown }
        XCTAssertEqual(app.controller.playlistDocuments.count, 1, "an untitled window is shown instead, never a blocking dialog")
        XCTAssertTrue(app.notices.shown.isEmpty)
    }

    func testNoSplashOrPlaceholderWindowExistsBeforeTheRealWindow() {
        let app = makeApp(resolver: TrackResolver())
        defer { app.tearDown() }
        let provider = DocumentLaunchWindows()
        var shown = false
        provider.presentFirstWindow { shown = true }
        spin { shown }
        let visible = NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }
        XCTAssertEqual(visible.count, 1)
        XCTAssertTrue(visible[0].windowController is PlaylistWindowController, "the first thing on screen is a playlist window")
    }
}

final class InfoPlistTests: XCTestCase {
    func plist() throws -> [String: Any] {
        try PropertyListSerialization.propertyList(from: Data(contentsOf: infoPlistURL), format: nil) as! [String: Any]
    }

    func testDeclaresExactlyTheThreeAudioTypesAndThePlaylistType() throws {        // story 1 TC-39 / story 4 TC-70, TC-71
        let types = try plist()["CFBundleDocumentTypes"] as! [[String: Any]]
        let declared = types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        XCTAssertEqual(Set(declared), ["public.mp3", "com.microsoft.waveform-audio", "public.mpeg-4-audio", "com.localplayer.playlist"])
        XCTAssertEqual(declared.count, 4)
        XCTAssertFalse(declared.contains { $0.contains("flac") || $0.contains("movie") || $0.contains("video") })
        let audio = types.filter { ($0["LSItemContentTypes"] as? [String]) != ["com.localplayer.playlist"] }
        XCTAssertTrue(audio.allSatisfy { $0["CFBundleTypeRole"] as? String == "Viewer" })
        let playlist = types.first { ($0["LSItemContentTypes"] as? [String]) == ["com.localplayer.playlist"] }!
        XCTAssertEqual(playlist["CFBundleTypeRole"] as? String, "Editor")
        XCTAssertEqual(playlist["NSDocumentClass"] as? String, "PlaylistDocument")
    }

    func testExportsThePlaylistTypeWithItsExtension() throws {
        let exported = try plist()["UTExportedTypeDeclarations"] as! [[String: Any]]
        XCTAssertEqual(exported.count, 1)
        XCTAssertEqual(exported[0]["UTTypeIdentifier"] as? String, playlistTypeIdentifier)
        let tags = exported[0]["UTTypeTagSpecification"] as! [String: Any]
        XCTAssertEqual(tags["public.filename-extension"] as? [String], [playlistFileExtension])
    }

    func testDoesNotChangeSystemDefaultsAndIsNotSandboxed() throws {
        let types = try plist()["CFBundleDocumentTypes"] as! [[String: Any]]
        XCTAssertFalse(types.contains { $0["LSHandlerRank"] as? String == "Default" }, "being the default handler stays the person's choice")
        let entitlements = try String(contentsOf: packageRoot.appendingPathComponent("Resources/LocalPlayer.entitlements"), encoding: .utf8)
        XCTAssertFalse(entitlements.contains("app-sandbox"))
    }
}
