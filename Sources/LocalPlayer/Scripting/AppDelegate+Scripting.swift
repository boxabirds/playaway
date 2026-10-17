import PlayawayCore
import AppKit

/// KVC properties for the scripting dictionary. NSApplication dispatches script property access to its delegate,
/// so they live here, and only the listed keys are handled.
extension AppDelegate {
    static let scriptKVCKeys: Set<String> = [
        "scriptIsPlaying", "scriptCurrentTrack", "scriptPosition", "scriptVolume", "scriptMuted", "scriptShuffle", "scriptRepeat",
    ]

    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        Self.scriptKVCKeys.contains(key)
    }

    @objc var scriptIsPlaying: Bool { actions?.isPlaying ?? false }
    @objc var scriptCurrentTrack: String { actions?.currentTrackName ?? "" }
    @objc var scriptPosition: Double { actions?.position ?? 0 }

    @objc var scriptVolume: Int {
        get { actions?.volumePercent ?? scriptVolumeMax }
        set { perform { try $0.setVolume(percent: newValue) } }
    }

    @objc var scriptMuted: Bool {
        get { actions?.isMuted ?? muteDefault }
        set { perform { try $0.setMuted(newValue) } }
    }

    @objc var scriptShuffle: Bool {
        get { actions?.shuffleOn ?? false }
        set { perform { try $0.setShuffle(newValue) } }
    }

    @objc var scriptRepeat: String {
        get { actions?.repeatName ?? RepeatMode.off.rawValue }
        set { perform { try $0.setRepeat(newValue) } }
    }

    /// A refused property change reports a numbered error on the command that is setting it.
    private func perform(_ body: (AppActions) throws -> Void) {
        guard let actions else { return }
        do { try body(actions) } catch let failure as ScriptFailure {
            _ = NSScriptCommand.current()?.fail(failure)
        } catch {}
    }
}

extension PlaylistDocument {
    @objc var scriptTrackCount: Int { playlist.tracks.count }
    @objc var scriptFilePath: String { fileURL?.path ?? "" }
    /// Story 22: the state the window shows, readable by script. Reading changes nothing.
    @objc var scriptICloudSync: Bool { sync.state == .on }
    /// Where each song's file is, in row order: location only, never whether it is downloaded (owner decision).
    @objc var scriptTrackICloudStates: [String] { playlist.tracks.map { isInICloud($0) ? ScriptTrackState.inICloud : ScriptTrackState.notInICloud } }
}

enum ScriptTrackState {
    static let inICloud = "in iCloud"
    static let notInICloud = "not in iCloud"
}
