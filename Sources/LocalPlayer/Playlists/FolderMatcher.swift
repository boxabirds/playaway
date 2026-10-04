import Foundation

protocol FolderMatching {
    func match(missing: [(id: UUID, fileName: String)], in folder: URL) -> [(id: UUID, url: URL)]
}

/// Looks only at the direct children of one folder, by file name, case-insensitively.
/// Reads a directory listing and nothing else, so by construction it cannot modify any file.
struct FolderMatcher: FolderMatching {
    func match(missing: [(id: UUID, fileName: String)], in folder: URL) -> [(id: UUID, url: URL)] {
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
