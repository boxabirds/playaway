import PlayawayCore
import AppKit

/// Reads the system appearance and accessibility display settings. There are no setters: the app never changes
/// them, overrides them, or offers a setting of its own that contradicts them.
final class AppearanceModel {
    private let appearance: () -> NSAppearance
    private let workspace: NSWorkspace

    init(appearance: @escaping () -> NSAppearance = { NSApp.effectiveAppearance }, workspace: NSWorkspace = .shared) {
        self.appearance = appearance
        self.workspace = workspace
    }

    var isDark: Bool { appearance().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
    var increaseContrast: Bool { workspace.accessibilityDisplayShouldIncreaseContrast }
    var reduceTransparency: Bool { workspace.accessibilityDisplayShouldReduceTransparency }
    var reduceMotion: Bool { workspace.accessibilityDisplayShouldReduceMotion }
}
