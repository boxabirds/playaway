import CoreGraphics

package enum CloudIconState: Equatable {
    case crossedOut        // local only
    case outline           // in iCloud and present
    case pieDownload
    case pieSync
    case exclamation       // download failed
    case locked            // iPhone and iPad: the song needs this device to be allowed to read its folder (story 41)
}

package enum SyncItemKind: Equatable { case song, playlist }

package enum CloudIconTapAction: Equatable {
    case openSyncDialog(SyncItemKind)
    case none
    case cancelDownload
    case cancelSync
    case retryDownload
    case restoreAccess     // a tap on a locked cloud starts the restore, as the banner does
}

/// What a tap (iPhone) or click (Mac) on a cloud icon does. There is no action that turns sync off.
package func cloudIconTapAction(state: CloudIconState, kind: SyncItemKind) -> CloudIconTapAction {
    switch state {
    case .crossedOut: return .openSyncDialog(kind)
    case .outline: return .none
    case .pieDownload: return .cancelDownload
    case .pieSync: return .cancelSync
    case .exclamation: return .retryDownload
    case .locked: return .restoreAccess
    }
}

/// iPhone adapter rule: every tappable cloud icon has at least this tappable area although the drawn icon is ~20pt.
package let minimumCloudIconTapSize = CGSize(width: 44, height: 44)

/// The drawn cloud icon is about this size; the tappable area above is larger on purpose.
package let cloudIconDrawnSize = CGSize(width: 20, height: 20)
