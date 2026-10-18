import Foundation

/// Provided by the Mac and iPhone adapters: start or cancel a platform download.
package protocol SongDownloading: AnyObject {
    func startDownload(of song: SongID)
    func cancelDownload(of song: SongID)
}

/// The shared player, as far as the coordinator needs it.
@MainActor
package protocol SongPlaybackStarting: AnyObject {
    func startPlayback(of song: SongID)
}
