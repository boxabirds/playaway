import Foundation

/// The three jobs a playlist window serves. The set is closed: a fourth needs a code change and a PRD change.
package enum Job: String, Codable, CaseIterable {
    case playFile = "play_file"
    case playPlaylist = "play_playlist"
    case managePlaylists = "manage_playlists"
}

package enum WindowKind: String, Codable, CaseIterable {
    case playlist
}

package struct ManifestEntry: Codable, Equatable {
    package init(elementID: String, job: Job) {
        self.elementID = elementID
        self.job = job
    }
    package let elementID: String
    package let job: Job
}

package enum ManifestError: Error, Equatable {
    case emptyFile
    case malformed
    case unknownWindowKind(String)
    case blankElementID(Int)
    case duplicateElementID(String)
    case unknownJob(String)
}

/// The single record of which elements a playlist window may show and which job each serves.
package struct UIManifest {
    package static let resourceName = "ui-manifest"
    package static let resourceExtension = "json"

    package let entries: [WindowKind: [ManifestEntry]]

    package init(entries: [WindowKind: [ManifestEntry]]) { self.entries = entries }

    package init(data: Data) throws {
        guard !data.isEmpty else { throw ManifestError.emptyFile }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let windows = root["windows"] as? [String: Any] else { throw ManifestError.malformed }
        var result: [WindowKind: [ManifestEntry]] = [:]
        for (kindName, value) in windows {
            guard let kind = WindowKind(rawValue: kindName) else { throw ManifestError.unknownWindowKind(kindName) }
            guard let list = value as? [[String: Any]] else { throw ManifestError.malformed }
            var seen = Set<String>()
            var entries: [ManifestEntry] = []
            for (index, raw) in list.enumerated() {
                guard let id = raw["element"] as? String, let jobName = raw["job"] as? String else { throw ManifestError.malformed }
                guard !id.trimmingCharacters(in: .whitespaces).isEmpty else { throw ManifestError.blankElementID(index) }
                guard let job = Job(rawValue: jobName) else { throw ManifestError.unknownJob(jobName) }
                guard seen.insert(id).inserted else { throw ManifestError.duplicateElementID(id) }
                entries.append(ManifestEntry(elementID: id, job: job))
            }
            result[kind] = entries
        }
        entries = result
    }

    /// Loads the bundled manifest. A missing resource is `emptyFile`; loading never falls back to an empty manifest.
    package static func load(bundle: Bundle = .main, overridePath: String? = ProcessInfo.processInfo.environment["LOCALPLAYER_UI_MANIFEST"]) throws -> UIManifest {
        let url: URL?
        if let overridePath { url = URL(fileURLWithPath: overridePath) }
        else { url = bundle.url(forResource: resourceName, withExtension: resourceExtension) }
        guard let url, let data = try? Data(contentsOf: url) else { throw ManifestError.emptyFile }
        return try UIManifest(data: data)
    }
}
