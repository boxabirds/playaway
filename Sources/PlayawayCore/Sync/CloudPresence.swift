import Foundation

/// Where a song's file is. "In iCloud" means inside the shared Playaway folder (owner decision 2026-10-13); whether
/// the file has been downloaded to this device is a separate matter.
package enum SongPresence: Equatable {
    /// Not in the Playaway folder, and the file is on this device.
    case localOnly
    /// Not in the Playaway folder, and the file is an iCloud Drive file that has not been downloaded to this device.
    case localOnlyNotOnDevice
    /// In the Playaway folder, and the file is on this device.
    case inCloudOnDevice
    /// In the Playaway folder, and the file has not been downloaded to this device.
    case inCloudNotOnDevice

    package var isOnDevice: Bool { self == .localOnly || self == .inCloudOnDevice }
}

/// The system's names for a ubiquitous file's download status.
package let ubiquitousStatusCurrent = "NSURLUbiquitousItemDownloadingStatusCurrent"
package let ubiquitousStatusDownloaded = "NSURLUbiquitousItemDownloadingStatusDownloaded"
package let ubiquitousStatusNotDownloaded = "NSURLUbiquitousItemDownloadingStatusNotDownloaded"

/// Current and Downloaded mean a copy is on the device; NotDownloaded means it is not. A status that is missing for an
/// iCloud Drive file is treated as present, so an unknown never blocks playing a file that is there. A song is "in
/// iCloud" only when it is inside the Playaway folder; where that cannot be determined it counts as not in iCloud.
package func songPresence(isUbiquitous: Bool, downloadingStatus: String?, isInPlaywayFolder: Bool) -> SongPresence {
    let notOnDevice = isUbiquitous && downloadingStatus == ubiquitousStatusNotDownloaded
    switch (isInPlaywayFolder, notOnDevice) {
    case (true, false): return .inCloudOnDevice
    case (true, true): return .inCloudNotOnDevice
    case (false, false): return .localOnly
    case (false, true): return .localOnlyNotOnDevice
    }
}

/// What a song row shows: the cloud icon, whether the row is dimmed, and the pie fraction while downloading.
package struct SongRowCloudDisplay: Equatable {
    package var icon: CloudIconState
    package var dimmed: Bool
    package var fraction: Double?

    package init(icon: CloudIconState, dimmed: Bool, fraction: Double?) {
        self.icon = icon; self.dimmed = dimmed; self.fraction = fraction
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
            case .localOnlyNotOnDevice: icon = .crossedOut; dimmed = true
            case .inCloudOnDevice: icon = .outline; dimmed = false
            case .inCloudNotOnDevice: icon = .outline; dimmed = true
            }
            fraction = nil
        }
    }
}
