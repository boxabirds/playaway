import Foundation

package protocol FolderMatching {
    func match(missing: [(id: UUID, fileName: String)], in folder: URL) -> [(id: UUID, url: URL)]
}

/// Looks only at the direct children of one folder, by file name, case-insensitively.
/// Reads a directory listing and nothing else, so by construction it cannot modify any file.
package struct FolderMatcher: FolderMatching {
    package init() {}
    package func match(missing: [(id: UUID, fileName: String)], in folder: URL) -> [(id: UUID, url: URL)] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return [] }
        var byName: [String: URL] = [:]
        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDirectory { byName[entry.lastPathComponent.lowercased()] = entry }
        }
        return missing.compactMap { item in
            byName[item.fileName.lowercased()].map { (id: item.id, url: $0) }
        }
    }
}

extension FolderMatcher {
    /// The one regular file in `folder` with exactly `size` bytes; nil for none, for several, for an unreadable folder.
    /// Several is nil on purpose: a guess between two files would play the wrong song.
    package func soleFile(ofSize size: Int64, in folder: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []) else { return nil }
        let candidates = entries.filter {
            let values = try? $0.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            return values?.isRegularFile == true && values?.fileSize.map(Int64.init) == size
        }
        return candidates.count == 1 ? candidates[0] : nil
    }
}
