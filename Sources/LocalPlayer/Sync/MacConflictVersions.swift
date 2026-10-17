import PlayawayCore
import Foundation

/// iCloud's conflict versions of a playlist file, through NSFileVersion. A file outside iCloud never has any. The
/// exact behaviour of resolving and removing versions on a real account is unverified (story 39, task 39.5).
struct MacConflictVersions: ConflictVersionReading {
    func unresolvedVersions(of url: URL) -> [ConflictVersion] {
        (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).compactMap { version in
            guard let date = version.modificationDate else { return nil }
            return ConflictVersion(url: version.url, modified: date)
        }
    }

    func markResolved(_ versions: [ConflictVersion], of url: URL) {
        for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        where versions.contains(where: { $0.url == version.url }) {
            version.isResolved = true
        }
    }
}
