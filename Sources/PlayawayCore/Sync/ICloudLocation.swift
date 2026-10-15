import Foundation

/// Whether a file is in iCloud. It is, only when it is strictly inside the shared Playaway folder (owner decision
/// 2026-10-13). Where that cannot be told, every caller treats the file as not in iCloud.
package enum LocationAnswer: Equatable {
    case insideContainer
    case outsideContainer
    case undeterminable
}

/// The one place the product decides "in iCloud". The Mac, the iPhone and every row and dialog call this.
/// `root` is the shared Playaway folder, nil when iCloud is not available.
package func locationAnswer(of url: URL, root: URL?) -> LocationAnswer {
    guard let root, url.isFileURL, root.isFileURL, !url.path.isEmpty, !root.path.isEmpty else { return .undeterminable }
    let rootPath = comparablePath(root)
    let filePath = comparablePath(url)
    let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    return filePath.hasPrefix(prefix) && filePath.count > prefix.count ? .insideContainer : .outsideContainer
}

/// Paths compared without being fooled by symlinks (`/var` is `/private/var`) or `..` parts.
private func comparablePath(_ url: URL) -> String {
    var path = url.standardizedFileURL.canonicalPath
    if path.hasPrefix("/private/") { path.removeFirst("/private".count) }
    while path.count > 1, path.hasSuffix("/") { path.removeLast() }
    return path
}
