import PlayawayCore
import AppKit

enum EnumerationError: Error, Equatable {
    case stateUnavailable(String)
}

protocol WindowEnumerating {
    func visibleElements(kind: WindowKind, in state: WindowState) throws -> [ObservedElement]
}

/// Walks a playlist window and lists its visible elements. An element is a view exposed to the accessibility
/// tree: a view with an identifier is recorded and not descended into; a visible accessibility element with no
/// identifier is reported as unidentified, so nothing can hide by being unnamed. Hidden and zero-size views and
/// everything inside them are left out. Reads only: nothing in the window, playback or any file is changed.
enum WindowElementWalker {
    static func elements(in window: NSWindow) -> [ObservedElement] {
        guard let content = window.contentView else { return [] }
        window.layoutIfNeeded()
        content.layoutSubtreeIfNeeded()
        var found: [ObservedElement] = []
        walk(content, into: &found)
        for accessory in window.titlebarAccessoryViewControllers {    // the title bar's own controls count too
            accessory.view.layoutSubtreeIfNeeded()
            walk(accessory.view, into: &found)
        }
        return found.sorted { ($0.id ?? "", $0.role) < ($1.id ?? "", $1.role) }
    }

    /// AppKit's own controls report no role until a window server round trip, so the class decides.
    static func role(of view: NSView) -> String {
        if let role = view.accessibilityRole(), role != .unknown { return role.rawValue }
        switch view {
        case is NSButton: return NSAccessibility.Role.button.rawValue
        case is NSSlider: return NSAccessibility.Role.slider.rawValue
        case let field as NSTextField: return (field.isEditable ? NSAccessibility.Role.textField : NSAccessibility.Role.staticText).rawValue
        case is NSScrollView: return NSAccessibility.Role.scrollArea.rawValue
        case is NSTableView: return NSAccessibility.Role.table.rawValue
        case is NSImageView: return NSAccessibility.Role.image.rawValue
        default: return NSAccessibility.Role.unknown.rawValue
        }
    }

    private static func isElement(_ view: NSView) -> Bool {
        view.isAccessibilityElement() || view is NSControl || view is NSScrollView || view is NSImageView
    }

    private static func walk(_ view: NSView, into found: inout [ObservedElement]) {
        guard !view.isHidden, view.frame.width > 0, view.frame.height > 0 else { return }
        let role = role(of: view)
        let id = view.accessibilityIdentifier()
        if !id.isEmpty {
            found.append(ObservedElement(id: id, role: role))
            return
        }
        if isElement(view) {
            found.append(ObservedElement(id: nil, role: role))
            return
        }
        view.subviews.forEach { walk($0, into: &found) }
    }
}
