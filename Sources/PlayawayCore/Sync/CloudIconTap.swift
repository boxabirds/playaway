import CoreGraphics

package enum CloudIconState: Equatable {
    case crossedOut        // local only
    case outline           // in iCloud and present
    case pieDownload
    case pieSync
    case exclamation       // download failed
}

package enum SyncItemKind: Equatable { case song, playlist }

package enum CloudIconTapAction: Equatable {
    case openSyncDialog(SyncItemKind)
    case none
    case cancelDownload
    case cancelSync
    case retryDownload
}

/// What a tap (iPhone) or click (Mac) on a cloud icon does. There is no action that turns sync off.
package func cloudIconTapAction(state: CloudIconState, kind: SyncItemKind) -> CloudIconTapAction {
    switch state {
    case .crossedOut: return .openSyncDialog(kind)
    case .outline: return .none
    case .pieDownload: return .cancelDownload
    case .pieSync: return .cancelSync
    case .exclamation: return .retryDownload
    }
}

/// iPhone adapter rule: every tappable cloud icon has at least this tappable area although the drawn icon is ~20pt.
package let minimumCloudIconTapSize = CGSize(width: 44, height: 44)
