import AppKit

protocol NoticePresenting: AnyObject {
    func show(_ notice: Notice)
}

/// Presents a standard alert, as a sheet on the front playlist window when there is one.
/// Holds at most one notice; showing a second replaces the first.
final class NoticePresenter: NoticePresenting {
    /// Tests turn alert animations off: tearing animated windows down in a headless test process has crashed.
    static var animatesAlerts = true

    private(set) var currentNotice: Notice?
    private var currentAlert: NSAlert?
    private var floatingWindow: NSWindow?
    private let hostWindow: () -> NSWindow?

    init(hostWindow: @escaping () -> NSWindow? = { NSApp?.keyWindow ?? NSApp?.mainWindow }) {
        self.hostWindow = hostWindow
    }

    var isShowingNotice: Bool { currentNotice != nil }

    func show(_ notice: Notice) {
        dismissCurrent()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = notice.title
        alert.informativeText = notice.detail
        alert.addButton(withTitle: Notice.dismissTitle)
        alert.window.isReleasedWhenClosed = false   // ARC owns it; a second release on close would crash
        if !Self.animatesAlerts { alert.window.animationBehavior = .none }
        currentNotice = notice
        currentAlert = alert
        if let host = hostWindow(), host.attachedSheet == nil {
            alert.beginSheetModal(for: host) { [weak self] _ in self?.finish(alert) }
        } else {
            presentFloating(alert)
        }
    }

    func dismissCurrent() {
        guard let alert = currentAlert else { return }
        if let parent = alert.window.sheetParent {
            parent.endSheet(alert.window, returnCode: .abort)
        }
        floatingWindow?.close()
        finish(alert)
    }

    private func presentFloating(_ alert: NSAlert) {
        alert.layout()
        let window = alert.window
        window.center()
        floatingWindow = window
        alert.buttons.first?.target = self
        alert.buttons.first?.action = #selector(dismissFloating(_:))
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func dismissFloating(_ sender: Any?) {
        dismissCurrent()
    }

    private func finish(_ alert: NSAlert) {
        guard currentAlert === alert else { return }
        currentAlert = nil
        currentNotice = nil
        floatingWindow = nil
    }
}
