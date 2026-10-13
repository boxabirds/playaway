import Foundation
import AVFoundation

/// What the player shows about a song: the title (the file name when the file has none), and artist, album and
/// artwork only when the file has them.
package struct TrackMetadata: Equatable {
    package var title: String
    package var artist: String?
    package var album: String?
    package var artworkData: Data?

    package init(title: String, artist: String? = nil, album: String? = nil, artworkData: Data? = nil) {
        self.title = title; self.artist = artist; self.album = album; self.artworkData = artworkData
    }

    package static func fallback(for url: URL) -> TrackMetadata {
        TrackMetadata(title: url.deletingPathExtension().lastPathComponent)
    }
}

package func loadTrackMetadata(for url: URL) async -> TrackMetadata {
    var result = TrackMetadata.fallback(for: url)
    let asset = AVURLAsset(url: url)
    guard let items = try? await asset.load(.commonMetadata) else { return result }
    func text(_ key: AVMetadataKey) async -> String? {
        let found = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: AVMetadataItem.identifier(forKey: key, keySpace: .common) ?? .commonIdentifierTitle)
        guard let first = found.first, let value = try? await first.load(.stringValue) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    if let title = await text(.commonKeyTitle) { result.title = title }
    result.artist = await text(.commonKeyArtist)
    result.album = await text(.commonKeyAlbumName)
    if let art = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork).first {
        result.artworkData = try? await art.load(.dataValue)
    }
    return result
}
