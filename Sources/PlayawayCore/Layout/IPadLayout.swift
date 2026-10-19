import Foundation

/// The iPad's arrangement decisions (story 38), as pure functions over what the system reports, so they are tested
/// without a simulator. The app maps SwiftUI's size class and type size onto these inputs.
public enum WidthClass: Equatable, Sendable { case compact, regular }

/// Which form a window takes: the stack (the iPhone's layout), or two columns (playlists, then its songs). The player is
/// never a column: it floats over the songs and opens as a card, as on the iPhone.
public enum ColumnPlan: Equatable, Sendable { case stack, two }

public enum IPadLayout {
    /// The test rig's rule for a fixed width: narrower than this is treated as compact (Split View one-third,
    /// Slide Over), because a fixed frame does not change the system's size class on its own.
    public static let rigCompactMaximumWidth: Double = 500

    /// A compact (or unknown) width is the stack; a regular width, in either orientation and at any type size, is two
    /// columns. The sidebar folds away by itself where there is no room for it (portrait, large type).
    public static func columnPlan(width: WidthClass?) -> ColumnPlan { width == .regular ? .two : .stack }

    /// What selecting a playlist does to the navigation state: in the stack it is the path; in columns it is the
    /// sidebar's selection, the path stays empty and the card is closed.
    public struct Selection: Equatable {
        public let selected: URL?
        public let path: [URL]
        public let cardOpen: Bool
        public init(selected: URL?, path: [URL], cardOpen: Bool) { self.selected = selected; self.path = path; self.cardOpen = cardOpen }
    }

    public static func selection(choosing url: URL?, plan: ColumnPlan, cardOpen: Bool) -> Selection {
        switch plan {
        case .stack: return Selection(selected: url, path: url.map { [$0] } ?? [], cardOpen: cardOpen)
        case .two: return Selection(selected: url, path: [], cardOpen: false)
        }
    }
}
