import Foundation

/// How often the playing position is written to storage while music plays. Writing on every tick is wasteful;
/// pausing, changing song, changing screen and leaving the app always write straight away.
package let listeningMemorySaveInterval: TimeInterval = 5

package let listeningMemoryDefaultsKey = "listeningMemory"

/// The song to carry on with: which playlist, which song in it, and how far in. Playlists are named by file name
/// because the folder's full address can change between app versions.
package struct ResumePoint: Codable, Equatable {
    package var playlistFileName: String
    package var trackID: UUID
    package var positionSeconds: Double

    package init(playlistFileName: String, trackID: UUID, positionSeconds: Double) {
        self.playlistFileName = playlistFileName
        self.trackID = trackID
        self.positionSeconds = positionSeconds
    }
}

/// What the app remembers between launches: the playlists the person had open, front last, and what was playing.
package struct ListeningMemory: Codable, Equatable {
    package var openPlaylists: [String]
    package var nowPlaying: ResumePoint?

    package static let empty = ListeningMemory(openPlaylists: [], nowPlaying: nil)

    package init(openPlaylists: [String], nowPlaying: ResumePoint?) {
        self.openPlaylists = openPlaylists
        self.nowPlaying = nowPlaying
    }

    /// Keeps only what still exists: open playlists whose file is still there, and the song only if its playlist
    /// and the song in it are both still there. A negative or non-finite position becomes the start of the song.
    package func restoring(existingPlaylists: Set<String>, trackExists: (String, UUID) -> Bool) -> ListeningMemory {
        var kept = self
        kept.openPlaylists = openPlaylists.filter { existingPlaylists.contains($0) }
        if var point = nowPlaying {
            if existingPlaylists.contains(point.playlistFileName), trackExists(point.playlistFileName, point.trackID) {
                if !point.positionSeconds.isFinite || point.positionSeconds < 0 { point.positionSeconds = 0 }
                kept.nowPlaying = point
            } else {
                kept.nowPlaying = nil
            }
        }
        return kept
    }
}

/// True when a playing-position write is due: never written yet, or the interval has passed.
package func shouldSavePosition(lastSaved: Date?, now: Date, interval: TimeInterval = listeningMemorySaveInterval) -> Bool {
    guard let lastSaved else { return true }
    return now.timeIntervalSince(lastSaved) >= interval
}

package protocol ListeningMemoryStoring {
    func load() -> ListeningMemory
    func save(_ memory: ListeningMemory)
}

/// Backed by the app's own defaults. Stored data that cannot be read gives an empty memory, never a crash.
package struct ListeningMemoryStore: ListeningMemoryStoring {
    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    package func load() -> ListeningMemory {
        guard let data = defaults.data(forKey: listeningMemoryDefaultsKey),
              let memory = try? JSONDecoder().decode(ListeningMemory.self, from: data) else { return .empty }
        return memory
    }

    package func save(_ memory: ListeningMemory) {
        if let data = try? JSONEncoder().encode(memory) { defaults.set(data, forKey: listeningMemoryDefaultsKey) }
    }
}
