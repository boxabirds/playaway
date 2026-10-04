import AppKit

/// The one Check for Updates item in the app menu.
enum UpdateMenu {
    static let title = "Check for Updates…"
    /// Sparkle's standard action name; the selector is the same one Sparkle's controller exposes.
    static let actionName = "checkForUpdates:"
    static let actionID = UpdaterController.checkForUpdatesActionID

    static var action: Selector { NSSelectorFromString(actionName) }

    static func makeItem(target: AnyObject?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        return item
    }
}
