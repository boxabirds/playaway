import PlayawayCore
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var services: AppServices!
    var launch: LaunchCoordinator!
    var updater: UpdaterController!
    var actions: AppActions!
    private let trace = LaunchTrace()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = AppMenu.makeMenuBar(target: self)
    }

    /// Space is Play/Pause in a playlist window. A local monitor sees the key before the responder chain, which the
    /// track list and an empty first responder both leave unhandled. A focused button keeps Space for pressing itself,
    /// and a text field keeps it for typing.
    private var spaceMonitor: Any?

    private func installSpaceShortcut() {
        spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, Self.isPlainSpace(event), let window = event.window,
                  window.windowController is PlaylistWindowController else { return event }
            let responder = window.firstResponder
            if responder is NSButton || responder is NSTextView || responder is NSSlider { return event }
            self.togglePlayPause(nil)
            return nil
        }
    }

    static func isPlainSpace(_ event: NSEvent) -> Bool {
        event.charactersIgnoringModifiers == " " && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
            && !event.isARepeat
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSpaceShortcut()
        let observers: [FirstWindowObserver] = [DocumentResolutionObserver(), updater]
        launch = LaunchCoordinator(trace: trace, observers: observers, windows: DocumentLaunchWindows())
        launch.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// With no window open, the Dock icon shows a playlist window straight away.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { _ = try? PlaylistDocumentController.current.openUntitledDocumentAndDisplay(true) }
        return false
    }

    /// Off: AppKit decides before its asynchronous window restoration has finished and adds an extra untitled window.
    /// `DocumentLaunchWindows` waits for restoration and opens the untitled playlist itself when there is none.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    /// Finder double-click and drop on the app icon. Each URL goes through the one shared open path.
    func application(_ application: NSApplication, open urls: [URL]) {
        services.openCoordinator.open(urls)
        ensureHostWindowForPlayback()
    }

    /// There is no main window. A single audio file shows in a playlist window's first group; when none is open
    /// a new untitled playlist window hosts it.
    func ensureHostWindowForPlayback() {
        guard LaunchState.firstWindowPresented || launch != nil else { return }
        let controller = PlaylistDocumentController.current
        if !controller.playlistDocuments.contains(where: { !$0.windowControllers.isEmpty }) {
            _ = try? controller.openUntitledDocumentAndDisplay(true)
        }
    }

    // MARK: Menu actions

    @objc func openAudioFile(_ sender: Any?) {
        guard let url = Self.chooseAudioFile() else { return }
        services.openCoordinator.open(url)
    }

    /// Space: the same Play/Pause the transport button does.
    @objc func togglePlayPause(_ sender: Any?) {
        services.transport.playPause()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updater?.checkForUpdates()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == NSSelectorFromString("checkForUpdates:") { return updater?.state == .idle }
        return true
    }

    static func chooseAudioFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .wav, .mpeg4Audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

extension AppDelegate {
    /// A sign-in or sign-out of iCloud shows the next time the app comes to the front, without a relaunch.
    func applicationDidBecomeActive(_ notification: Notification) {
        services?.cloud.refresh()
        // Not at launch: the launch itself resolves each playlist once its window is up.
        if LaunchState.firstWindowPresented { PlaylistDocumentController.current.refreshOpenPlaylists() }
    }
}
