import Foundation

/// One permission the person gave on this device: a folder under iCloud Drive, and the bookmark that reopens it on
/// this device (Apple, "Providing access to directories": a folder picked in the document picker may be read
/// recursively, new items included, and kept across launches as a bookmark). Grants are per device by Apple's design;
/// the playlist carries the portable path, this carries the permission.
package struct FolderGrant: Codable, Equatable {
    /// Relative to the iCloud Drive root, "Mixdowns" or "Mixdowns/Live".
    package var drivePath: String
    package var bookmark: Data

    package init(drivePath: String, bookmark: Data) {
        self.drivePath = drivePath
        self.bookmark = bookmark
    }
}

package protocol FolderGrantStoring {
    func load() -> [FolderGrant]
    func save(_ grants: [FolderGrant])
}

/// The grants as a JSON file. An unreadable or absent file is an empty list.
package final class FolderGrantFileStore: FolderGrantStoring {
    private let url: URL
    package init(url: URL) { self.url = url }

    package func load() -> [FolderGrant] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([FolderGrant].self, from: data)) ?? []
    }

    package func save(_ grants: [FolderGrant]) {
        guard let data = try? JSONEncoder().encode(grants) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

package final class InMemoryFolderGrantStore: FolderGrantStoring {
    package private(set) var grants: [FolderGrant]
    package init(_ grants: [FolderGrant] = []) { self.grants = grants }
    package func load() -> [FolderGrant] { grants }
    package func save(_ grants: [FolderGrant]) { self.grants = grants }
}

/// What this device has learned about where songs are, kept per device and never in the shared playlist: a song found
/// somewhere other than where it was saved (`moved`: saved drive path to the path found), and a song the person
/// pointed at with Locate (`located`: saved drive path to a bookmark of the chosen file).
package struct DeviceMatches: Codable, Equatable {
    package var moved: [String: String] = [:]
    package var located: [String: Data] = [:]
    package init(moved: [String: String] = [:], located: [String: Data] = [:]) { self.moved = moved; self.located = located }
}

package protocol DeviceMatchStoring {
    func load() -> DeviceMatches
    func save(_ matches: DeviceMatches)
}

package final class DeviceMatchFileStore: DeviceMatchStoring {
    private let url: URL
    package init(url: URL) { self.url = url }
    package func load() -> DeviceMatches {
        guard let data = try? Data(contentsOf: url) else { return DeviceMatches() }
        return (try? JSONDecoder().decode(DeviceMatches.self, from: data)) ?? DeviceMatches()
    }
    package func save(_ matches: DeviceMatches) {
        guard let data = try? JSONEncoder().encode(matches) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

package final class InMemoryDeviceMatchStore: DeviceMatchStoring {
    package private(set) var matches: DeviceMatches
    package init(_ matches: DeviceMatches = DeviceMatches()) { self.matches = matches }
    package func load() -> DeviceMatches { matches }
    package func save(_ matches: DeviceMatches) { self.matches = matches }
}

/// The iPhone's and iPad's roots: the Playaway container directly, iCloud Drive through the folders the person allowed.
/// A grant's URL, once resolved, is kept open for the app's life: the grant is the app's standing permission to read
/// that folder, not a one-read lease.
package final class GrantedCloudRoots: CloudRoots {
    package var playawayDocuments: URL?
    private let store: FolderGrantStoring
    private let matchStore: DeviceMatchStoring
    private var deviceMatches: DeviceMatches
    private var locatedURLs: [String: URL] = [:]
    private let drivePath: (URL) -> String?
    private let makeBookmark: (URL) -> Data?
    private let resolveBookmark: (Data) -> URL?
    private var grants: [FolderGrant]
    private var opened: [String: URL] = [:]

    /// `drivePath` reads a picked folder's place under iCloud Drive (nil outside it); `makeBookmark` and
    /// `resolveBookmark` are Foundation's unless a test says otherwise. The default resolution starts security-scoped
    /// access and keeps it.
    package init(playawayDocuments: URL?, store: FolderGrantStoring, matchStore: DeviceMatchStoring = InMemoryDeviceMatchStore(),
                 drivePath: @escaping (URL) -> String? = { CloudFolder.relativePath(inDrive: $0.path) },
                 makeBookmark: @escaping (URL) -> Data? = { try? $0.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil) },
                 resolveBookmark: @escaping (Data) -> URL? = GrantedCloudRoots.resolveKeepingAccess) {
        self.playawayDocuments = playawayDocuments
        self.store = store
        self.matchStore = matchStore
        deviceMatches = matchStore.load()
        self.drivePath = drivePath
        self.makeBookmark = makeBookmark
        self.resolveBookmark = resolveBookmark
        grants = store.load()
    }

    package static func resolveKeepingAccess(_ bookmark: Data) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    package var granted: [FolderGrant] { grants }

    /// Records a folder the person picked. Nil, and nothing recorded, for a folder that is not under iCloud Drive (or
    /// is the root itself, which the picker cannot grant), or that cannot be bookmarked.
    @discardableResult
    package func grant(pickedFolder url: URL) -> FolderGrant? {
        guard let path = drivePath(url).map(Self.normalized), !path.isEmpty, let bookmark = makeBookmark(url) else { return nil }
        let grant = FolderGrant(drivePath: path, bookmark: bookmark)
        grants.removeAll { $0.drivePath == path }
        grants.append(grant)
        opened[path] = url
        store.save(grants)
        return grant
    }

    /// Forgets a grant (one that turned out to cover none of the songs it was asked for).
    package func revoke(drivePath: String) {
        guard let grant = grants.first(where: { $0.drivePath == drivePath }) else { return }
        drop(grant)
    }

    /// Whether a grant covers the path: the grant's folder is the file's folder or one above it, and its bookmark still
    /// opens a folder on this device.
    package func covers(_ path: CloudPath) -> Bool { grantURL(covering: path) != nil }

    package func url(for path: CloudPath) -> URL? {
        switch path {
        case .playawayFolder(let rest):
            return playawayDocuments.flatMap { appending(rest, to: $0) }
        case .iCloudDrive(let rest):
            if let located = locatedURL(for: rest) { return located }
            if let actual = deviceMatches.moved[rest] {
                if let url = urlUnderGrant(actual), Self.exists(url) { return url }
                forget(moved: rest)                 // the file it was found at is gone: ask again
            }
            return urlUnderGrant(rest)
        }
    }

    /// The folder to ask for when this device cannot reach the path: its top folder, unless something here already covers it.
    package func accessNeeded(for path: CloudPath) -> String? {
        guard case .iCloudDrive(let rest) = path else { return nil }
        if locatedURL(for: rest) != nil { return nil }
        if let actual = deviceMatches.moved[rest], covers(.iCloudDrive(actual)) { return nil }
        return covers(path) ? nil : path.topFolder
    }

    /// Whether this device reaches the song only through what the person gave it here: a folder grant, a match found
    /// under one, or a Locate. A song found any other way (its own reference) says the folder is readable anyway.
    package func reaches(_ path: CloudPath) -> Bool {
        guard case .iCloudDrive(let rest) = path else { return false }
        return deviceMatches.located[rest] != nil || deviceMatches.moved[rest] != nil || covers(path)
    }

    /// Remembers where songs were found other than where they were saved, per device.
    package func remember(_ moved: [String: String]) {
        guard !moved.isEmpty else { return }
        deviceMatches.moved.merge(moved) { _, new in new }
        matchStore.save(deviceMatches)
    }

    /// Locate: the person chose this file for the song saved at `path`; kept per device as a bookmark.
    @discardableResult
    package func locate(savedPath path: String, file: URL) -> Bool {
        guard let bookmark = makeBookmark(file) else { return false }
        deviceMatches.located[path] = bookmark
        locatedURLs[path] = file
        matchStore.save(deviceMatches)
        return true
    }

    private func locatedURL(for path: String) -> URL? {
        if let url = locatedURLs[path], Self.exists(url) { return url }
        guard let bookmark = deviceMatches.located[path] else { return nil }
        guard let url = resolveBookmark(bookmark), Self.exists(url) else {
            deviceMatches.located[path] = nil; locatedURLs[path] = nil; matchStore.save(deviceMatches)
            return nil
        }
        locatedURLs[path] = url
        return url
    }

    private func urlUnderGrant(_ rest: String) -> URL? {
        guard let (grant, folder) = grantURL(covering: .iCloudDrive(rest)) else { return nil }
        return appending(String(rest.dropFirst(grant.drivePath.count)), to: folder)
    }

    private func forget(moved path: String) {
        deviceMatches.moved[path] = nil
        matchStore.save(deviceMatches)
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) || iCloudPlaceholderExists(for: url)
    }

    /// The one folder to ask for next: the top folder most of the unfound songs share. A folder in which some song of
    /// the same playlist IS found on this device is never asked for: the device can read it, so its unfound songs are
    /// gone or renamed, not out of reach (the phone that made the playlist must never be asked about its own folder).
    package static func folderToAsk(for unfound: [CloudPath], found: [CloudPath] = []) -> String? {
        let readable = Set(found.compactMap(\.topFolder))
        var counts: [String: Int] = [:]
        for path in unfound { if let top = path.topFolder, !readable.contains(top) { counts[top, default: 0] += 1 } }
        return counts.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key
    }

    private func grantURL(covering path: CloudPath) -> (FolderGrant, URL)? {
        guard case .iCloudDrive(let rest) = path else { return nil }
        let normalized = Self.normalized(rest)
        let candidates = grants.filter { normalized == $0.drivePath || normalized.hasPrefix($0.drivePath + "/") }
            .sorted { $0.drivePath.count > $1.drivePath.count }        // the nearest folder first
        for grant in candidates {
            if let folder = openedFolder(for: grant) { return (grant, folder) }
        }
        return nil
    }

    private func openedFolder(for grant: FolderGrant) -> URL? {
        if let url = opened[grant.drivePath], Self.isDirectory(url) { return url }
        guard let url = resolveBookmark(grant.bookmark), Self.isDirectory(url) else {
            drop(grant)
            return nil
        }
        opened[grant.drivePath] = url
        return url
    }

    /// A grant whose bookmark no longer opens a folder (permission withdrawn, folder gone) is forgotten, so the
    /// notice asks for it again.
    private func drop(_ grant: FolderGrant) {
        grants.removeAll { $0.drivePath == grant.drivePath }
        opened[grant.drivePath] = nil
        store.save(grants)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func normalized(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
    }
}
