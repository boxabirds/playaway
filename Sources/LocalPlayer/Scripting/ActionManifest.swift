import PlayawayCore
import AppKit

/// One user action, listed once: how a person does it and how a script does it.
struct ManifestAction: Equatable {
    let id: String
    let description: String
    let uiBinding: String?
    let scriptBinding: String?
}

/// Standard macOS items that are not scripted by this player.
enum ExcludedSystemItems {
    static let ids: Set<String> = ["about", "quit", "hide", "services", "windowMenu", "helpMenu"]
    /// Hide Others and Show All belong to Hide; the Window menu's items belong to the Window menu.
    static let menuTitles: Set<String> = ["About Playaway", "Hide Playaway", "Hide Others", "Show All", "Services",
                                          "Quit Playaway", "Minimize", "Zoom", "Bring All to Front"]
    /// System document actions the app does not script (the PRD excludes "system document actions").
    static let documentMenuTitles: Set<String> = ["Open…", "Open Recent", "Clear Menu", "Close", "Save", "Undo", "Redo", "Select All"]
}

/// The single list of actions behind the windows, the menus and the scripting dictionary. 20 today.
enum ActionManifest {
    static let actions: [ManifestAction] = [
        ManifestAction(id: "openFile", description: "Open an audio file and play it.", uiBinding: "File > Open Audio File…", scriptBinding: "open audio file"),
        ManifestAction(id: "play", description: "Play, or resume when paused.", uiBinding: "Play button, File > Play/Pause", scriptBinding: "play"),
        ManifestAction(id: "playTrack", description: "Play a track of an open playlist, as a double-click does.", uiBinding: "Track row double-click", scriptBinding: "play track"),
        ManifestAction(id: "pause", description: "Pause, keeping the position.", uiBinding: "Pause button", scriptBinding: "pause"),
        ManifestAction(id: "stop", description: "Stop and return to the start.", uiBinding: "Stop button", scriptBinding: "stop"),
        ManifestAction(id: "seek", description: "Move to a position in the track.", uiBinding: "Position slider", scriptBinding: "seek"),
        ManifestAction(id: "next", description: "Play the next track.", uiBinding: "Next button", scriptBinding: "next track"),
        ManifestAction(id: "previous", description: "Play the previous track.", uiBinding: "Previous button", scriptBinding: "previous track"),
        ManifestAction(id: "volume", description: "Set the player's own volume.", uiBinding: "Volume slider", scriptBinding: "volume"),
        ManifestAction(id: "mute", description: "Mute or unmute.", uiBinding: "Mute button", scriptBinding: "muted"),
        ManifestAction(id: "shuffle", description: "Turn shuffle on or off.", uiBinding: "Shuffle button", scriptBinding: "shuffle"),
        ManifestAction(id: "repeat", description: "Set repeat to off, all or one.", uiBinding: "Repeat button", scriptBinding: "repeat mode"),
        ManifestAction(id: "newPlaylist", description: "Make a new playlist.", uiBinding: "File > New Playlist", scriptBinding: "new playlist"),
        ManifestAction(id: "renamePlaylist", description: "Rename a saved playlist.", uiBinding: "File > Rename…", scriptBinding: "rename playlist"),
        ManifestAction(id: "addTrack", description: "Add an audio file to a playlist.", uiBinding: "File > Add Files…", scriptBinding: "add track"),
        ManifestAction(id: "removeTrack", description: "Remove a track from a playlist.", uiBinding: "Edit > Remove from Playlist", scriptBinding: "remove track"),
        ManifestAction(id: "reorderTrack", description: "Move a track to another position.", uiBinding: "Drag a track row", scriptBinding: "move track"),
        ManifestAction(id: "locate", description: "Point a missing track at its file.", uiBinding: "Track row context menu > Locate…", scriptBinding: "locate track"),
        ManifestAction(id: "checkForUpdates", description: "Check for a newer version.", uiBinding: "Playaway > Check for Updates…", scriptBinding: "check for updates"),
        ManifestAction(id: "syncPlaylist", description: "Turn iCloud sync on for a playlist.", uiBinding: "Title-bar cloud button", scriptBinding: "sync playlist"),
    ]
}

struct ParityResult: Equatable {
    var missingScript: [String]
    var missingUI: [String]
    var passed: Bool { missingScript.isEmpty && missingUI.isEmpty }
}

/// Build-time parity gate: every app-specific action must have a script entry and every script entry an action.
enum ParityGate {
    static func checkParity(manifest: [ManifestAction], dictionaryEntries: Set<String>, excluded: Set<String>) -> ParityResult {
        let ui = manifest.filter { $0.uiBinding != nil && !excluded.contains($0.id) }
        let missingScript = ui.filter { action in
            guard let binding = action.scriptBinding else { return true }
            return !dictionaryEntries.contains(binding)
        }.map(\.id)
        let bound = Set(ui.compactMap(\.scriptBinding))
        let missingUI = dictionaryEntries.subtracting(bound).sorted()
        return ParityResult(missingScript: missingScript.sorted(), missingUI: missingUI)
    }

    /// Every app-specific menu item must be a manifest action, an excluded system item or a system document action.
    static func menuItemsWithoutScriptBinding(in menu: NSMenu, manifest: [ManifestAction]) -> [String] {
        let known = Set(manifest.compactMap(\.uiBinding).compactMap { $0.split(separator: ">").last.map { String($0).trimmingCharacters(in: .whitespaces) } })
        var unbound: [String] = []
        func visit(_ menu: NSMenu) {
            for item in menu.items where !item.isSeparatorItem {
                if let submenu = item.submenu, ["Services", "Open Recent", "Window", "Help"].contains(item.title) || submenu.items.isEmpty {
                    if !ExcludedSystemItems.menuTitles.contains(item.title), !ExcludedSystemItems.documentMenuTitles.contains(item.title),
                       !["Window", "Help"].contains(item.title) { unbound.append(item.title) }
                    continue
                }
                if let submenu = item.submenu { visit(submenu); continue }
                let title = item.title
                if known.contains(title) || ExcludedSystemItems.menuTitles.contains(title) || ExcludedSystemItems.documentMenuTitles.contains(title) { continue }
                unbound.append(title)
            }
        }
        visit(menu)
        return unbound
    }

    /// Reads command names and writable application properties out of an sdef: the entries a script can act with.
    static func dictionaryEntries(sdef data: Data) -> Set<String> {
        let parser = SdefEntryParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return parser.entries
    }
}

private final class SdefEntryParser: NSObject, XMLParserDelegate {
    var entries = Set<String>()
    private var classStack: [String] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "class": classStack.append(attributeDict["name"] ?? "")
        case "command": if let name = attributeDict["name"] { entries.insert(name) }
        case "property":
            if classStack.last == "application", attributeDict["access"] == "rw", let name = attributeDict["name"] { entries.insert(name) }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "class" { _ = classStack.popLast() }
    }
}

/// `--check-script-parity <sdef>`: the release gate. Prints every action with no script entry, every script entry
/// with no action, and every app-specific menu item that is neither; exits non-zero on any.
func runParityGateCheck(sdefPath: String) -> Int32 {
    guard let data = FileManager.default.contents(atPath: sdefPath), !data.isEmpty else {
        FileHandle.standardError.write(Data("parity gate: cannot read the scripting dictionary at \(sdefPath)\n".utf8))
        return 1
    }
    let result = ParityGate.checkParity(manifest: ActionManifest.actions,
                                        dictionaryEntries: ParityGate.dictionaryEntries(sdef: data),
                                        excluded: ExcludedSystemItems.ids)
    let unbound = ParityGate.menuItemsWithoutScriptBinding(in: AppMenu.makeMenuBar(target: nil), manifest: ActionManifest.actions)
    for id in result.missingScript { print("FAIL action '\(id)' has no scripting command or property") }
    for entry in result.missingUI { print("FAIL scripting entry '\(entry)' has no on-screen action") }
    for title in unbound { print("FAIL menu item '\(title)' has no scripting equivalent") }
    let failed = !result.passed || !unbound.isEmpty
    print(failed ? "script parity: FAILED" : "script parity: ok (\(ActionManifest.actions.count) actions)")
    return failed ? 1 : 0
}
