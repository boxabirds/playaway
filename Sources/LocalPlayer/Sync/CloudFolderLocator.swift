import PlayawayCore
import Foundation
import Combine

/// Where the Playaway folder of iCloud Drive is on this Mac, asked again whenever the app becomes active, so a
/// sign-in or sign-out shows without a relaunch. The folder is the one the iPhone app's container puts in
/// ~/Library/Mobile Documents; the app is not sandboxed and reads it directly. Tests supply a stand-in.
final class CloudFolderLocator {
    private let find: () -> URL?
    private(set) var root: URL?
    /// Fires after `root` changed.
    let changes = PassthroughSubject<Void, Never>()
    /// The system's answer for whether a file is in iCloud Drive (anywhere in it), nil when it cannot be asked; the
    /// same question the phone asks, so both apps sort songs the same way. Tests answer it from a stand-in folder.
    var isUbiquitous: (URL) -> Bool? = { url in try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem }

    init(find: @escaping () -> URL?) {
        self.find = find
        root = find()
    }

    var availability: ICloudAvailability { root.map { .available(root: $0) } ?? .unavailable }

    func refresh() {
        let now = find()
        guard now != root else { return }
        root = now
        changes.send()
    }
}
