import Foundation
import CryptoKit

/// Where finished sheets are kept so a song is transcribed once.
package protocol LyricSheetStoring: Sendable {
    func load(songKey: String) -> LyricSheet?
    func save(_ sheet: LyricSheet) throws
    func delete(songKey: String)
    func deleteAll()
}

/// One JSON file per song in a folder of the app's own.
package struct FileLyricSheetStore: LyricSheetStoring {
    package let directory: URL

    package init(directory: URL) {
        self.directory = directory
    }

    /// The app's usual place: Application Support/Lyrics.
    package static func standard() -> FileLyricSheetStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return FileLyricSheetStore(directory: base.appendingPathComponent("Lyrics", isDirectory: true))
    }

    private func url(for songKey: String) -> URL { directory.appendingPathComponent(songKey).appendingPathExtension("json") }

    package func load(songKey: String) -> LyricSheet? {
        guard let data = try? Data(contentsOf: url(for: songKey)),
              let sheet = try? JSONDecoder().decode(LyricSheet.self, from: data),
              sheet.version == LyricSheet.formatVersion else { return nil }
        return sheet
    }

    package func save(_ sheet: LyricSheet) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(sheet)
        try data.write(to: url(for: sheet.songKey), options: .atomic)
    }

    package func delete(songKey: String) { try? FileManager.default.removeItem(at: url(for: songKey)) }

    package func deleteAll() { try? FileManager.default.removeItem(at: directory) }
}

/// Identifies a song file for the store: its name, size and modification date, hashed. The same file on another device
/// gives the same key; an edited file gives a new one.
package func lyricSongKey(for url: URL) -> String? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let size = attributes[.size] as? NSNumber else { return nil }
    let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let material = "\(url.lastPathComponent)|\(size.int64Value)|\(Int64(modified))"
    return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
}
