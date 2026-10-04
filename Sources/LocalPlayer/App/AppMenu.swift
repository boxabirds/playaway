import AppKit

/// The standard macOS menu bar: application menu, File, Window, Help. Standard names and shortcuts.
enum AppMenu {
    static let appName = "LocalPlayer"

    static func makeMenuBar(target: AnyObject?) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenuItem(title: appName, menu: appMenu(target: target)))
        main.addItem(submenuItem(title: "File", menu: fileMenu(target: target)))
        main.addItem(submenuItem(title: "Edit", menu: editMenu()))
        let window = windowMenu()
        main.addItem(submenuItem(title: "Window", menu: window))
        NSApp?.windowsMenu = window
        let help = NSMenu(title: "Help")
        main.addItem(submenuItem(title: "Help", menu: help))
        NSApp?.helpMenu = help
        return main
    }

    private static func submenuItem(title: String, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    private static func appMenu(target: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: appName)
        menu.addItem(item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(UpdateMenu.makeItem(target: target))
        menu.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        services.submenu = servicesMenu
        NSApp?.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(item("Hide \(appName)", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu(target: AnyObject?) -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Playlist", #selector(NSDocumentController.newDocument(_:)), "n"))
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))
        menu.addItem(item("Open Audio File…", NSSelectorFromString("openAudioFile:"), "o", [.command, .option], target: target))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Save", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("Rename…", #selector(NSDocument.rename(_:))))
        menu.addItem(item("Play/Pause", NSSelectorFromString("togglePlayPause:"), " ", [], target: target))
        menu.addItem(.separator())
        menu.addItem(item("Add Files…", NSSelectorFromString("addFiles:"), "a", [.command, .shift]))
        return menu
    }

    /// Undo and redo for playlist edits, Select All for the track list, and removing the selected tracks.
    /// Cut, Copy and Paste are left out: nothing in a playlist window can be cut or pasted.
    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Select All", #selector(NSResponder.selectAll(_:)), "a"))
        menu.addItem(item("Remove from Playlist", NSSelectorFromString("removeSelectedTracks:"), "\u{8}", .command))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}
