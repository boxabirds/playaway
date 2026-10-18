import Foundation

/// One file under a folder the person has allowed (story 41), as a listing sees it.
package struct TreeEntry: Equatable {
    package var relativePath: String      // inside the chosen folder, "Live/Demo Live.wav"
    package var name: String
    package var size: Int64
    package init(relativePath: String, name: String, size: Int64) {
        self.relativePath = relativePath; self.name = name; self.size = size
    }

    /// The size of a file that iCloud has not downloaded: its real length is not on this device.
    package static let unknownSize: Int64 = -1
    /// ".Aftershock s1.m4a.icloud" is the stand-in for "Aftershock s1.m4a"; nil for any other name.
    package static func placeholderTarget(of name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud"), name.count > ".x.icloud".count - 1 else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }
}

/// Reads a folder's whole tree in one pass, so restoring a 300-song playlist lists the folder once, not once per song.
package protocol FolderListing: Sendable {
    /// `progress` is told how many items have been looked at (every fifty, and at the end); `isCancelled` is asked as it goes,
    /// and a cancelled listing returns what it has.
    func entries(under folder: URL, progress: (Int) -> Void, isCancelled: () -> Bool) -> [TreeEntry]
}

extension FolderListing {
    package func entries(under folder: URL) -> [TreeEntry] { entries(under: folder, progress: { _ in }, isCancelled: { false }) }
}

package struct SystemFolderListing: FolderListing {
    package init() {}
    /// How often the count of items looked at is reported while walking.
    static let progressEvery = 50

    package func entries(under folder: URL, progress: (Int) -> Void, isCancelled: () -> Bool) -> [TreeEntry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return [] }
        let base = folder.canonicalPath + "/"
        var found: [TreeEntry] = [], looked = 0
        for case let url as URL in walker {
            if isCancelled() { break }
            looked += 1
            if looked % Self.progressEvery == 0 { progress(looked) }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let path = url.canonicalPath
            guard path.hasPrefix(base) else { continue }
            var relative = String(path.dropFirst(base.count)), name = url.lastPathComponent, size = Int64(values.fileSize ?? 0)
            if let real = TreeEntry.placeholderTarget(of: name) {
                // A song iCloud has not downloaded is listed as ".Name.icloud": it is Name, whose size is not known here.
                relative = (relative as NSString).deletingLastPathComponent.isEmpty ? real : ((relative as NSString).deletingLastPathComponent as NSString).appendingPathComponent(real)
                name = real; size = TreeEntry.unknownSize
            } else if name.hasPrefix(".") { continue }
            found.append(TreeEntry(relativePath: relative, name: name, size: size))
        }
        progress(looked)
        return found
    }
}

/// A song to find again: where it was inside the chosen folder (when it was in it), its name and, when recorded, its size.
package struct SongProbe: Equatable {
    package var id: UUID
    package var savedPlace: String?
    package var fileName: String
    package var fileSize: Int64?
    package init(id: UUID, savedPlace: String?, fileName: String, fileSize: Int64?) {
        self.id = id; self.savedPlace = savedPlace; self.fileName = fileName; self.fileSize = fileSize
    }
}

package enum MatchOutcome: Equatable {
    case matched(String)      // the relative path of the file found
    case ambiguous
    case none
}

/// Finds each song in the listing: first at its saved place; else by name and size; a size that was never recorded
/// matches by name alone, and only when exactly one file has that name. Two candidates are never chosen between, and a
/// file of the same name but another size is not the song.
package func matchSongs(_ probes: [SongProbe], in entries: [TreeEntry]) -> [UUID: MatchOutcome] {
    var byPath: [String: TreeEntry] = [:]
    var byName: [String: [TreeEntry]] = [:]
    for entry in entries {
        byPath[entry.relativePath.lowercased()] = entry
        byName[entry.name.lowercased(), default: []].append(entry)
    }
    var outcomes: [UUID: MatchOutcome] = [:]
    for probe in probes {
        if let place = probe.savedPlace, let entry = byPath[place.lowercased()] { outcomes[probe.id] = .matched(entry.relativePath); continue }
        let sameName = byName[probe.fileName.lowercased()] ?? []
        let candidates = probe.fileSize.map { size in sameName.filter { $0.size == size || $0.size == TreeEntry.unknownSize } } ?? sameName
        switch candidates.count {
        case 0: outcomes[probe.id] = MatchOutcome.none     // explicit: a bare .none would remove the entry (Optional.none)
        case 1: outcomes[probe.id] = .matched(candidates[0].relativePath)
        default: outcomes[probe.id] = .ambiguous
        }
    }
    return outcomes
}
