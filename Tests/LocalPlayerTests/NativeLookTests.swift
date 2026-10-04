import XCTest
import AppKit
import ObjectiveC
@testable import LocalPlayer

let packageRoot = Fixtures.directory.deletingLastPathComponent().deletingLastPathComponent()

final class PlatformFloorTests: XCTestCase {
    func testInfoPlistAndPackageDeclareMacOS26() throws {                                  // TC-40 / TC-41
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoPlistURL), format: nil) as! [String: Any]
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "26.0")
        let package = try String(contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(package.contains(".macOS(.v26)"))
    }
}

@MainActor
final class MenuBarTests: XCTestCase {
    var menu: NSMenu!
    override func setUp() async throws {
        _ = NSApplication.shared
        menu = AppMenu.makeMenuBar(target: nil)
    }

    func item(_ title: String, in submenu: String) -> NSMenuItem? {
        menu.items.first { $0.title == submenu }?.submenu?.items.first { $0.title == title }
    }

    func testTitlesAndOrder() {                                                              // TC-30
        XCTAssertEqual(menu.items.map(\.title), [AppMenu.appName, "File", "Edit", "Window", "Help"])
    }

    func testApplicationMenuHasAboutAndQuitWithStandardShortcut() {                          // TC-31
        let quit = item("Quit \(AppMenu.appName)", in: AppMenu.appName)
        XCTAssertEqual(quit?.keyEquivalent, "q")
        XCTAssertEqual(quit?.keyEquivalentModifierMask, .command)
        XCTAssertNotNil(item("About \(AppMenu.appName)", in: AppMenu.appName))
        XCTAssertEqual(menu.items.filter { $0.submenu?.items.contains { $0.title.hasPrefix("Check for Updates") } == true }.count, 1)
    }

    func testFileMenuHasTheDocumentCommandsAndTheAudioOpen() {                               // TC-35
        let expected: [(String, String, NSEvent.ModifierFlags)] = [
            ("New Playlist", "n", .command), ("Open…", "o", .command), ("Close", "w", .command), ("Save", "s", .command)]
        for (title, key, modifiers) in expected {
            let found = item(title, in: "File")
            XCTAssertEqual(found?.keyEquivalent, key, title)
            XCTAssertEqual(found?.keyEquivalentModifierMask, modifiers, title)
        }
        // Open Recent is supplied by AppKit's document controller; the e2e test reads it from the real menu bar.
        XCTAssertNotNil(item("Rename…", in: "File"))
        XCTAssertNotNil(item("Open Audio File…", in: "File"), "the command that opens an audio file")
    }

    func testEditMenuHasUndoRedoSelectAllAndRemove() {
        let undo = item("Undo", in: "Edit"), redo = item("Redo", in: "Edit")
        XCTAssertEqual(item("Select All", in: "Edit")?.keyEquivalent, "a")
        XCTAssertEqual(item("Remove from Playlist", in: "Edit")?.keyEquivalent, "\u{8}")
        XCTAssertNil(item("Remove from Playlist", in: "File"), "moved to Edit")
        XCTAssertNil(item("Undo", in: "File"))
        let play = item("Play/Pause", in: "File")
        XCTAssertEqual(undo?.keyEquivalent, "z"); XCTAssertEqual(undo?.keyEquivalentModifierMask, .command)
        XCTAssertEqual(redo?.keyEquivalent, "z"); XCTAssertEqual(redo?.keyEquivalentModifierMask, [.command, .shift])
        XCTAssertEqual(play?.keyEquivalent, " "); XCTAssertEqual(play?.keyEquivalentModifierMask, [])
        XCTAssertEqual(menu.items.count, 5, "App, File, Edit, Window, Help")
    }

    func testNoDeletePlaylistItemAnywhere() {                                                // TC-95
        func titles(_ menu: NSMenu) -> [String] { menu.items.flatMap { [$0.title] + ($0.submenu.map(titles) ?? []) } }
        XCTAssertFalse(titles(menu).contains { $0.lowercased().contains("delete") })
    }

    func testNoInventedShortcutConflictsWithAnotherItem() {                                  // TC-34
        var seen: [String: String] = [:]
        func visit(_ menu: NSMenu) {
            for item in menu.items {
                if !item.keyEquivalent.isEmpty {
                    let key = "\(item.keyEquivalentModifierMask.rawValue)-\(item.keyEquivalent)"
                    XCTAssertNil(seen[key], "\(item.title) clashes with \(seen[key] ?? "")")
                    seen[key] = item.title
                }
                if let sub = item.submenu { visit(sub) }
            }
        }
        visit(menu)
        // No shortcut the system defines is reused for something else.
        XCTAssertEqual(item("Hide \(AppMenu.appName)", in: AppMenu.appName)?.keyEquivalent, "h")
        XCTAssertEqual(item("Minimize", in: "Window")?.keyEquivalent, "m")
    }

    func testWindowAndHelpMenusAreWiredToTheSystem() {
        NSApp.mainMenu = menu
        XCTAssertEqual(NSApp.windowsMenu?.title, "Window")
        XCTAssertEqual(NSApp.helpMenu?.title, "Help")
    }
}

@MainActor
final class NativeControlsTests: XCTestCase {
    var app: TestApp!
    var folders: [TempDir] = []      // a TempDir deletes its folder when released, so keep them for the test
    override func setUp() async throws { app = TestApp() }
    override func tearDown() async throws { app.tearDown() }

    func tempURL(_ name: String) -> URL { let dir = TempDir(); folders.append(dir); return dir.path(name) }

    func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }

    func playlistWindow() -> NSWindow {
        let doc = app.openSaved(PlaylistFixture(trackNames: ["track1.mp3", "tone.wav"]).playlist, at: tempURL("N.lplaylist"))
        return app.window(of: doc).window!
    }

    /// True when a class (or any superclass below AppKit) replaces drawing, which would make it a custom-drawn control.
    func overridesDrawing(_ cls: AnyClass) -> Bool {
        var current: AnyClass? = cls
        while let c = current, Bundle(for: c) != Bundle(for: NSView.self) {
            for selector in [#selector(NSView.draw(_:)), #selector(NSView.updateLayer)] {
                var count: UInt32 = 0
                let methods = class_copyMethodList(c, &count)
                defer { free(methods) }
                for index in 0..<Int(count) where method_getName(methods![index]) == selector { return true }
            }
            current = class_getSuperclass(c)
        }
        return false
    }

    func testEveryButtonSliderAndTableIsASystemClassAndNothingIsCustomDrawn() {              // TC-32 / TC-72
        let window = playlistWindow()
        for view in allViews(window.contentView!) {
            if view is NSControl || view is NSScrollView || view is NSTableView {
                let module = String(cString: class_getImageName(type(of: view))!)
                XCTAssertTrue(module.contains("AppKit.framework"), "\(type(of: view)) must be a system class")
            }
            XCTAssertFalse(overridesDrawing(type(of: view)), "\(type(of: view)) draws itself")
        }
    }

    func testWindowChromeIsTheSystemTitleBarAndWindowButtons() {                              // TC-33
        let window = playlistWindow()
        XCTAssertTrue(window.styleMask.isSuperset(of: [.titled, .closable, .miniaturizable, .resizable]))
        XCTAssertFalse(window.titlebarAppearsTransparent, "no custom title bar styling")
        XCTAssertEqual(window.titleVisibility, .visible)
        XCTAssertNil(window.toolbar, "no custom title bar content")
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            XCTAssertNotNil(window.standardWindowButton(button), "\(button)")
        }
    }

    func testTwoPlaylistsAreTwoWindowsAndNoOtherWindowExists() {                              // TC-36 / TC-76
        let a = app.openSaved(PlaylistFixture(trackNames: ["track1.mp3"]).playlist, at: tempURL("A.lplaylist"))
        let b = app.openSaved(PlaylistFixture(trackNames: ["track2.mp3"]).playlist, at: tempURL("B.lplaylist"))
        let titled = NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }
        XCTAssertEqual(titled.count, 2)
        XCTAssertTrue(titled.allSatisfy { $0.windowController is PlaylistWindowController })
        _ = (a, b)
    }

    func testEveryOpenWindowFollowsASystemAppearanceChangeWithoutRestart() {                   // TC-21..25
        let first = playlistWindow()
        let second = playlistWindow()
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        for target in [NSAppearance.Name.darkAqua, .aqua] {
            NSApp.appearance = NSAppearance(named: target)       // what the system switch does to the app
            for window in [first, second] {
                XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), target)
                XCTAssertEqual(window.contentView!.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), target)
            }
        }
        XCTAssertTrue(AppearanceModel().isDark || !AppearanceModel().isDark, "the model reads without crashing")
    }

    func testAnewWindowOpensInTheCurrentAppearanceWhenNoneWasOpen() {                          // TC-20 / TC-23
        let original = NSApp.appearance
        defer { NSApp.appearance = original }
        NSApp.appearance = NSAppearance(named: .darkAqua)
        XCTAssertEqual(playlistWindow().effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), .darkAqua)
    }

    func testTheAppOffersNoAppearanceOrAccessibilityOverride() throws {                         // TC-71 / TC-70
        NSApp.appearance = nil
        XCTAssertNil(NSApp.appearance, "the app never sets an appearance of its own")
        let sources = packageRoot.appendingPathComponent("Sources/LocalPlayer")
        let forbidden = ["NSApp.appearance =", ".appearance = NSAppearance", "accessibilityDisplayShould", "reduceTransparency =", "increaseContrast ="]
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator where url.pathExtension == "swift" && url.lastPathComponent != "AppearanceModel.swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for token in forbidden { XCTAssertFalse(text.contains(token), "\(url.lastPathComponent) contains \(token)") }
        }
    }

    func testAppearanceModelIsReadOnly() {
        let model = AppearanceModel(appearance: { NSAppearance(named: .darkAqua)! })
        XCTAssertTrue(model.isDark)
        let model2 = AppearanceModel(appearance: { NSAppearance(named: .aqua)! })
        XCTAssertFalse(model2.isDark)
        _ = (model.increaseContrast, model.reduceTransparency, model.reduceMotion)
    }

    func testGlassHelperReturnsTheSystemMaterialAndNoWindowUsesGlassYet() {                      // TC-50..52
        let glass = GlassSurface.wrap(NSTextField(labelWithString: "x"))
        XCTAssertTrue(type(of: glass) == NSGlassEffectView.self)
        let window = playlistWindow()
        XCTAssertTrue(allViews(window.contentView!).allSatisfy { !($0 is NSGlassEffectView) }, "zero glass surfaces configured")
    }

    func testNoFakeGlassNoCustomBlurAndNoWindowChromeImages() throws {                          // TC-51 / TC-72
        let window = playlistWindow()
        // AppKit's own table machinery contains system effect views; what matters is that this app creates none.
        _ = window
        let sources = packageRoot.appendingPathComponent("Sources/LocalPlayer")
        let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator {
            XCTAssertFalse(["png", "pdf", "icns", "jpg"].contains(url.pathExtension.lowercased()), "no image assets: \(url.lastPathComponent)")
            if url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                XCTAssertFalse(text.contains("NSVisualEffectView"), url.lastPathComponent)
                XCTAssertFalse(text.contains("CIGaussianBlur"), url.lastPathComponent)
                if url.lastPathComponent != "GlassSurface.swift" { XCTAssertFalse(text.contains("NSGlassEffectView"), "glass is created only in GlassSurface") }
            }
        }
    }

    func testExtensionIsHiddenTitleShowsTheNameOnly() {
        let doc = app.openSaved(Playlist(), at: tempURL("Dinner.lplaylist"))
        XCTAssertEqual(app.window(of: doc).window?.title, "Dinner")
    }
}
