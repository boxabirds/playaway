import Foundation

/// Playlist-level iCloud sync, shared by the Mac and the iPhone (story 18). A playlist is synced when its file is
/// strictly inside the Playaway folder in iCloud Drive (owner decision 2026-10-13: "in iCloud" is a location).
/// Turning sync on for a playlist elsewhere asks once, then moves the file to Playaway/<name>/<name>.lplaylist, the
/// layout the iPhone writes. There is no way back: turning sync off is not a feature anywhere (owner decision
/// 2026-10-13), so nothing here can set a synced playlist back to not synced.
package enum ICloudSyncState: Equatable, Sendable {
    case off, on
}

/// The person's answer to the Playlist dialog. Dismissing the dialog is answered as `dontSync` by the presenter.
package enum PlaylistChoice: Equatable, Sendable {
    case move, dontSync
}

/// The 'Sync with iCloud: Playlist' dialog, defined once; each platform only draws it.
package enum PlaylistPrompt {
    package static let title = "Sync with iCloud: Playlist"
    package static let message = "For this to be turned on, this playlist must be moved to iCloud"
    package static let moveLabel = "Move"
    package static let dontSyncLabel = "Don't Sync"
}

@MainActor
package protocol PlaylistPromptPresenting: AnyObject {
    func askPlaylistChoice() async -> PlaylistChoice
}

/// Whether this device can reach the Playaway folder in iCloud Drive. `root` is that folder when it can.
package enum ICloudAvailability: Equatable, Sendable {
    case available(root: URL)
    case unavailable

    /// The one-line reason shown beside a disabled sync switch and read by VoiceOver (wording a proposal, PRD 3).
    package static let unavailableReason = "iCloud is not available"

    package var root: URL? {
        if case .available(let root) = self { return root }
        return nil
    }
}

/// How the playlist's sync switch looks and reads. The switch is not a per-song status icon: it has its own symbols.
package struct ICloudButtonPresentation: Equatable, Sendable {
    package static let offSymbol = "icloud.slash"
    package static let onSymbol = "icloud.fill"
    package static let label = "iCloud sync for this playlist"

    package let symbolName: String
    package let accessibilityLabel: String
    /// "on" or "off", followed by the reason when the switch is disabled, so VoiceOver reads both.
    package let accessibilityValue: String
    package let isEnabled: Bool
    package let reason: String?

    package init(state: ICloudSyncState, availability: ICloudAvailability) {
        symbolName = state == .on ? Self.onSymbol : Self.offSymbol
        accessibilityLabel = Self.label
        let stateWord = state == .on ? "on" : "off"
        switch availability {
        case .available:
            isEnabled = true
            reason = nil
            accessibilityValue = stateWord
        case .unavailable:
            isEnabled = false
            reason = ICloudAvailability.unavailableReason
            accessibilityValue = "\(stateWord), \(ICloudAvailability.unavailableReason)"
        }
    }
}

/// The one answer to "is this playlist synced": its file is strictly inside the Playaway folder.
package func playlistSyncState(of file: URL?, root: URL?) -> ICloudSyncState {
    guard let file, let root, isStrictlyInside(file, folder: root) else { return .off }
    return .on
}

package enum PlaylistSyncOutcome: Equatable {
    /// Sync is on; the playlist's file is here (unchanged when it already was in iCloud).
    case on(URL)
    /// The person chose not to sync; nothing changed.
    case left
    /// The move did not happen; nothing changed. The text is for the person.
    case failed(String)
    /// This device cannot reach iCloud; nothing was asked or changed.
    case unavailable
}

/// Moves the playlist file. The Mac moves it through its open document; the iPhone hands it to the system.
@MainActor
package protocol PlaylistMoving {
    func movePlaylist(from source: URL, to destination: URL) async throws
}

@MainActor
package struct PlaylistSyncCore {
    private let availability: ICloudAvailability
    private let mover: PlaylistMoving
    private let presenter: PlaylistPromptPresenting
    private let fileManager: FileManager

    package init(availability: ICloudAvailability, mover: PlaylistMoving, presenter: PlaylistPromptPresenting,
                 fileManager: FileManager = .default) {
        self.availability = availability
        self.mover = mover
        self.presenter = presenter
        self.fileManager = fileManager
    }

    package func state(of file: URL?) -> ICloudSyncState { playlistSyncState(of: file, root: availability.root) }

    /// Turns sync on for the playlist at `url`. Asks only when the file is outside the Playaway folder; moves only on
    /// Move; a refused or failed move leaves the file exactly where it was, with no folder left behind.
    package func turnOn(playlistAt url: URL) async -> PlaylistSyncOutcome {
        guard let root = availability.root else { return .unavailable }
        if state(of: url) == .on { return .on(url) }
        guard await presenter.askPlaylistChoice() == .move else { return .left }
        let name = url.deletingPathExtension().lastPathComponent
        let location = PlaylistLibrary.cloudPlaylistLocation(in: root, name: name)
        guard !fileManager.fileExists(atPath: location.directory.path) else {
            return .failed("A playlist named “\(name)” is already in iCloud, so this one was not moved.")
        }
        do { try fileManager.createDirectory(at: location.directory, withIntermediateDirectories: true) }
        catch { return .failed("The playlist could not be moved to iCloud: \(error.localizedDescription)") }
        do {
            try await mover.movePlaylist(from: url, to: location.file)
        } catch {
            try? fileManager.removeItem(at: location.directory)
            return .failed("The playlist could not be moved to iCloud: \(error.localizedDescription)")
        }
        return .on(location.file)
    }
}
