import Foundation

/// Whether a file is in iCloud, meaning it is an iCloud Drive file the person can reach from their other devices
/// (owner decision 2026-10-15: it does not have to be in the Playaway folder). Where that cannot be told, every
/// caller treats the file as not in iCloud.
package enum ICloudAnswer: Equatable {
    case inICloud
    case notInICloud
    case undeterminable
}

/// The one place the product decides "in iCloud". `isUbiquitous` is the system's answer for the file (nil when it
/// could not be asked, for example when iCloud is unavailable). The Mac, the iPhone and every row and dialog call this.
package func iCloudAnswer(isUbiquitous: Bool?) -> ICloudAnswer {
    guard let isUbiquitous else { return .undeterminable }
    return isUbiquitous ? .inICloud : .notInICloud
}

/// Whether a file is strictly inside a folder, compared without being fooled by symlinks (`/var` is `/private/var`) or
/// `..` parts. Used to keep every transfer destination inside the Playaway folder, not to decide "in iCloud".
package func isStrictlyInside(_ file: URL, folder: URL?) -> Bool {
    guard let folder, file.isFileURL, folder.isFileURL, !file.path.isEmpty, !folder.path.isEmpty else { return false }
    let root = comparablePath(folder)
    let path = comparablePath(file)
    let prefix = root.hasSuffix("/") ? root : root + "/"
    return path.hasPrefix(prefix) && path.count > prefix.count
}

private func comparablePath(_ url: URL) -> String {
    var path = url.standardizedFileURL.canonicalPath
    if path.hasPrefix("/private/") { path.removeFirst("/private".count) }
    while path.count > 1, path.hasSuffix("/") { path.removeLast() }
    return path
}
