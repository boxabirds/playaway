import Foundation

package struct SongID: Hashable {
    package let raw: String
    package init(_ raw: String) { self.raw = raw }
}

/// Where a song's file is, from this device's point of view. One type for the Mac, the iPhone and the row rule.
package enum DownloadState: Equatable {
    case onThisDevice
    case notOnThisDevice
    case downloading(Double)   // fraction 0...1
    case failed

    package static let failedAccessibilityLabel = "Download failed, tap to retry"

    /// A row is dimmed whenever the file is not on this device.
    package var rowIsDimmed: Bool { self != .onThisDevice }

    /// The exclamation mark replaces the cloud icon only for a failed download.
    package var showsExclamationMark: Bool { self == .failed }

    package var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}
