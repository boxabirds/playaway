import Foundation

package enum TransferChoice: Equatable {
    case move
    case copy
}

package struct TransferItem: Equatable {
    package let id: UUID
    package let source: URL
    package init(id: UUID, source: URL) { self.id = id; self.source = source }
}

package struct TransferFailure: Equatable {
    package let id: UUID
    package let fileName: String
    package let reason: String
}

package struct TransferResult: Equatable {
    package var moved = 0
    package var copied = 0
    /// Songs the person asked to move that were copied instead: on another volume, or read-only.
    package var copiedInstead = 0
    package var failures: [TransferFailure] = []
    /// Where each handled song is now, by its id. A failed song is not in here and stays where it was.
    package var newLocations: [UUID: URL] = [:]
    package init() {}
}

/// What the runner needs from the file system, so a test can stand in for iCloud and for a second disk.
package protocol TransferFileSystem {
    func createDirectory(_ url: URL) throws
    func exists(_ url: URL) -> Bool
    func sameVolume(_ a: URL, _ b: URL) -> Bool
    /// True when the original can be removed from where it is, which a move needs.
    func canRemove(_ url: URL) -> Bool
    func move(_ source: URL, to destination: URL) throws
    func copy(_ source: URL, to destination: URL) throws
    func remove(_ url: URL)
}

/// The folder a playlist's songs go into: `Playaway/<playlist name>/` in the shared container. The name is made a safe
/// single folder name, so a destination can never be outside the Playaway folder. Nil when iCloud is unavailable.
package func transferDestination(root: URL?, playlistName: String) -> URL? {
    guard let root else { return nil }
    let unsafe = CharacterSet(charactersIn: "/:\\")
    var name = playlistName.components(separatedBy: unsafe).joined(separator: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    while name.hasPrefix(".") { name.removeFirst() }
    if name.isEmpty { name = "Playlist" }
    if name.count > 100 { name = String(name.prefix(100)) }
    return root.appendingPathComponent(name, isDirectory: true)
}

/// Moves or copies songs into the destination folder. A move is a real move only where it can be: same disk and the
/// original removable. Otherwise the song is copied and the original is left, and the song counts as copied instead.
/// One song failing never stops the others, never touches its original, and never overwrites a file already there.
package func runTransfer(_ items: [TransferItem], choice: TransferChoice, destination: URL,
                         fileSystem: TransferFileSystem) -> TransferResult {
    var result = TransferResult()
    do { try fileSystem.createDirectory(destination) }
    catch {
        result.failures = items.map { TransferFailure(id: $0.id, fileName: $0.source.lastPathComponent, reason: error.localizedDescription) }
        return result
    }
    for item in items {
        let name = item.source.lastPathComponent
        let target = destination.appendingPathComponent(name)
        guard !fileSystem.exists(target) else {
            result.failures.append(TransferFailure(id: item.id, fileName: name, reason: "A file with that name is already in the folder."))
            continue
        }
        do {
            switch choice {
            case .copy:
                try fileSystem.copy(item.source, to: target)
                result.copied += 1
            case .move:
                if fileSystem.sameVolume(item.source, destination), fileSystem.canRemove(item.source) {
                    try fileSystem.move(item.source, to: target)
                    result.moved += 1
                } else {
                    try fileSystem.copy(item.source, to: target)
                    result.copiedInstead += 1
                }
            }
            result.newLocations[item.id] = target
        } catch {
            fileSystem.remove(target)         // never leave half a file behind; the original was not touched
            result.failures.append(TransferFailure(id: item.id, fileName: name, reason: error.localizedDescription))
        }
    }
    return result
}

/// The real file system.
package struct SystemTransferFileSystem: TransferFileSystem {
    private let fileManager: FileManager
    package init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    package func createDirectory(_ url: URL) throws { try fileManager.createDirectory(at: url, withIntermediateDirectories: true) }
    package func exists(_ url: URL) -> Bool { fileManager.fileExists(atPath: url.path) }
    package func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey]
        let first = try? a.resourceValues(forKeys: keys).volumeIdentifier as? NSObject
        let second = try? b.resourceValues(forKeys: keys).volumeIdentifier as? NSObject
        guard let first, let second else { return false }
        return first.isEqual(second)
    }
    package func canRemove(_ url: URL) -> Bool { fileManager.isWritableFile(atPath: url.deletingLastPathComponent().path) }
    package func move(_ source: URL, to destination: URL) throws { try coordinated(source, destination) { try fileManager.moveItem(at: $0, to: $1) } }
    package func copy(_ source: URL, to destination: URL) throws { try coordinated(source, destination) { try fileManager.copyItem(at: $0, to: $1) } }
    package func remove(_ url: URL) { try? fileManager.removeItem(at: url) }

    private func coordinated(_ source: URL, _ destination: URL, _ operation: (URL, URL) throws -> Void) throws {
        var coordinationError: NSError?
        var thrown: Error?
        NSFileCoordinator().coordinate(writingItemAt: source, options: .forMoving, writingItemAt: destination,
                                       options: .forReplacing, error: &coordinationError) { from, to in
            do { try operation(from, to) } catch { thrown = error }
        }
        if let coordinationError { throw coordinationError }
        if let thrown { throw thrown }
    }
}
