import Foundation

/// Where a song's file is. "In iCloud" means an iCloud Drive file, anywhere in iCloud Drive (owner decision 2026-10-15);
/// whether the file has been downloaded to this device is a separate matter.
package enum SongPresence: Equatable {
    /// Not in iCloud: only on this device.
    case localOnly
    /// In iCloud, and the file is on this device.
    case inCloudOnDevice
    /// In iCloud, and the file has not been downloaded to this device.
    case inCloudNotOnDevice

    package var isOnDevice: Bool { self != .inCloudNotOnDevice }
}

/// The system's names for a ubiquitous file's download status.
package let ubiquitousStatusCurrent = "NSURLUbiquitousItemDownloadingStatusCurrent"
package let ubiquitousStatusDownloaded = "NSURLUbiquitousItemDownloadingStatusDownloaded"
package let ubiquitousStatusNotDownloaded = "NSURLUbiquitousItemDownloadingStatusNotDownloaded"

/// Current and Downloaded mean a copy is on the device; NotDownloaded means it is not. A status that is missing for an
/// iCloud Drive file is treated as present, so an unknown never blocks playing a file that is there.
package func songPresence(isUbiquitous: Bool, downloadingStatus: String?) -> SongPresence {
    guard isUbiquitous else { return .localOnly }
    return downloadingStatus == ubiquitousStatusNotDownloaded ? .inCloudNotOnDevice : .inCloudOnDevice
}

/// What a song row shows: the cloud icon, whether the row is dimmed, and the pie fraction while downloading.
package struct SongRowCloudDisplay: Equatable {
    package var icon: CloudIconState
    package var dimmed: Bool
    package var fraction: Double?

    package init(icon: CloudIconState, dimmed: Bool, fraction: Double?) {
        self.icon = icon; self.dimmed = dimmed; self.fraction = fraction
    }

    /// A song that needs this device to be allowed to read its folder shows the locked cloud whatever else is known:
    /// there is nothing to download or play until the person restores access (story 41).
    package init(needsAccess: Bool, presence: SongPresence, tracked: DownloadState?) {
        if needsAccess { self.init(icon: .locked, dimmed: false, fraction: nil) }
        else { self.init(presence: presence, tracked: tracked) }
    }

    /// The display of a song that cannot be found: the locked cloud, the question-mark cloud, or none (a song that was on
    /// this device and is gone keeps today's behaviour: no cloud, and the not-found message when tapped).
    package static func unfound(_ kind: UnfoundKind) -> SongRowCloudDisplay? {
        switch kind {
        case .needsAccess: return SongRowCloudDisplay(icon: .locked, dimmed: false, fraction: nil)
        case .elsewhere: return SongRowCloudDisplay(icon: .elsewhere, dimmed: false, fraction: nil)
        case .gone: return nil
        }
    }

    /// `tracked` is what the download coordinator knows about this song, if anything. An active download or a
    /// failure wins over what the file system says.
    package init(presence: SongPresence, tracked: DownloadState?) {
        switch tracked {
        case .downloading(let fraction)?:
            icon = .pieDownload; dimmed = true; self.fraction = fraction
        case .failed?:
            icon = .exclamation; dimmed = true; fraction = nil
        default:
            switch presence {
            case .localOnly: icon = .crossedOut; dimmed = false
            case .inCloudOnDevice: icon = .outline; dimmed = false
            case .inCloudNotOnDevice: icon = .outline; dimmed = true
            }
            fraction = nil
        }
    }
}
