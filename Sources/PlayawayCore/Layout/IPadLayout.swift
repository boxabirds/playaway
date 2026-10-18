import Foundation

/// The iPad's arrangement decisions (story 38), as pure functions over what the system reports, so they are tested
/// without a simulator. The app maps SwiftUI's size class and type size onto these inputs.
public enum WidthClass: Equatable, Sendable { case compact, regular }

/// Which columns a window shows: the stack (the iPhone's layout), two columns, or all three.
public enum ColumnPlan: Equatable, Sendable { case stack, two, three }

/// How the player column lays itself out: the words below the controls, or beside them.
public enum PlayerLayout: Equatable, Sendable { case stacked, sideBySide }

public enum IPadLayout {
    /// A regular-width window shows three columns from this width up. A starting value, to be measured on the
    /// 11-inch and adjusted; below it two columns.
    public static let threeColumnMinimumWidth: Double = 1000
    /// The player column puts the words beside the controls from this width up.
    public static let lyricsBesideMinimumWidth: Double = 600
    /// The test rig's rule for a fixed width: narrower than this is treated as compact (Split View one-third,
    /// Slide Over), because a fixed frame does not change the system's size class on its own.
    public static let rigCompactMaximumWidth: Double = 500

    /// `width` nil is treated as compact; an accessibility type size never gets three columns; a width that has not
    /// been measured yet (zero) never gets three columns either.
    public static func columnPlan(width: WidthClass?, isAccessibilityTypeSize: Bool, windowWidth: Double) -> ColumnPlan {
        guard width == .regular else { return .stack }
        if isAccessibilityTypeSize { return .two }
        return windowWidth >= threeColumnMinimumWidth ? .three : .two
    }

    public static func playerLayout(columnWidth: Double) -> PlayerLayout {
        columnWidth >= lyricsBesideMinimumWidth ? .sideBySide : .stacked
    }

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
        case .two, .three: return Selection(selected: url, path: [], cardOpen: false)
        }
    }
}
