import PlayawayCore
import AppKit

/// Cocoa scripting entry points. Each command only extracts its arguments and calls `AppActions`.
private func actions() -> AppActions? { (NSApp.delegate as? AppDelegate)?.actions }

class LocalPlayerCommand: NSScriptCommand {
    func run(_ body: (AppActions) throws -> Any?) -> Any? {
        guard let actions = actions() else { return fail(.notReady) }
        do { return try body(actions) } catch let failure as ScriptFailure { return fail(failure) } catch {
            return fail(.invalid(error.localizedDescription))
        }
    }

    var stringArgument: String? { directParameter as? String }
    var intDirect: Int? { (directParameter as? NSNumber)?.intValue }
    func string(_ key: String) -> String? { evaluatedArguments?[key] as? String }
    func int(_ key: String) -> Int? { (evaluatedArguments?[key] as? NSNumber)?.intValue }
}

@objc(OpenAudioFileCommand) final class OpenAudioFileCommand: LocalPlayerCommand {
    override func performDefaultImplementation() -> Any? {
        run { try $0.openFile(path: stringArgument ?? ""); return nil }
    }
}

@objc(PlayCommand) final class PlayCommand: LocalPlayerCommand {
    override func performDefaultImplementation() -> Any? { run { try $0.play(); return nil } }
}

@objc(PauseCommand) final class PauseCommand: LocalPlayerCommand {
    override func performDefaultImplementation() -> Any? { run { try $0.pause(); return nil } }
}

@objc(StopCommand) final class StopCommand: LocalPlayerCommand {
    override func performDefaultImplementation() -> Any? { run { try $0.stop(); return nil } }
}

@objc(SeekCommand) final class SeekCommand: LocalPlayerCommand {
    override func performDefaultImplementation() -> Any? {
        run { actions in
            guard let seconds = (evaluatedArguments?["seconds"] as? NSNumber)?.doubleValue else { throw ScriptFailure.invalid("Seek needs a time in seconds.") }
            try actions.seek(toSeconds: seconds)
            return nil
        }
    }
}

@objc(NextTrackCommand) final class NextTrackCommand: LocalPlayerCommand {
    override func performDefaultImplementation() -> Any? { run { try $0.next(); return nil } }
}

@objc(PreviousTrackCommand) final class PreviousTrackCommand: LocalPlayerCommand {
    override func performDefaultImplementation() -> Any? { run { try $0.previous(); return nil } }
}

@objc(PlayTrackCommand) final class PlayTrackCommand: LocalPlayerCommand {
    override func performDefaultImplementation() -> Any? {
        run { actions in
            guard let position = intDirect, let playlist = string("playlist") else { throw ScriptFailure.invalid("Play track needs a position and a playlist.") }
            try actions.playTrack(position, inPlaylist: playlist)
            return nil
        }
    }
}

@objc(NewPlaylistCommand) final class NewPlaylistCommand: LocalPlayerCommand {
    override func performDefaultImplementation() -> Any? {
        run { try $0.newPlaylist(named: string("name"), atPath: string("path")) }
    }
}

@objc(SyncPlaylistCommand) final class SyncPlaylistCommand: LocalPlayerCommand {
    override func performDefaultImplementation() -> Any? {
        run { actions in
            guard let name = stringArgument else { throw ScriptFailure.invalid("Sync playlist needs the playlist's name.") }
            return try actions.syncPlaylist(name, answering: string("playlistAnswer"), files: string("filesAnswer")).record
        }
    }
}

@objc(RenamePlaylistCommand) final class RenamePlaylistCommand: LocalPlayerCommand {
    override func performDefaultImplementation() -> Any? {
        run { actions in
            guard let name = stringArgument, let newName = string("newName") else { throw ScriptFailure.invalid("Rename needs the playlist and a new name.") }
            try actions.renamePlaylist(name, to: newName)
            return nil
        }
    }
}

@objc(AddTrackCommand) final class AddTrackCommand: LocalPlayerCommand {
    override func performDefaultImplementation() -> Any? {
        run { actions in
            guard let file = stringArgument, let playlist = string("playlist") else { throw ScriptFailure.invalid("Add track needs a file and a playlist.") }
            try actions.addTrack(path: file, toPlaylist: playlist, files: string("filesAnswer"))
            return nil
        }
    }
}

@objc(RemoveTrackCommand) final class RemoveTrackCommand: LocalPlayerCommand {
    override func performDefaultImplementation() -> Any? {
        run { actions in
            guard let position = intDirect, let playlist = string("playlist") else { throw ScriptFailure.invalid("Remove track needs a position and a playlist.") }
            try actions.removeTrack(position, fromPlaylist: playlist)
            return nil
        }
    }
}

@objc(MoveTrackCommand) final class MoveTrackCommand: LocalPlayerCommand {
    override func performDefaultImplementation() -> Any? {
        run { actions in
            guard let from = intDirect, let to = int("position"), let playlist = string("playlist") else {
                throw ScriptFailure.invalid("Move track needs a position, a new position and a playlist.")
            }
            try actions.moveTrack(from, to: to, inPlaylist: playlist)
            return nil
        }
    }
}

@objc(LocateTrackCommand) final class LocateTrackCommand: LocalPlayerCommand {
    override func performDefaultImplementation() -> Any? {
        run { actions in
            guard let position = intDirect, let playlist = string("playlist"), let file = string("file") else {
                throw ScriptFailure.invalid("Locate track needs a position, a playlist and a file.")
            }
            try actions.locateTrack(position, inPlaylist: playlist, withFile: file)
            return nil
        }
    }
}

@objc(CheckForUpdatesCommand) final class CheckForUpdatesCommand: LocalPlayerCommand {
    override func performDefaultImplementation() -> Any? { run { try $0.checkForUpdates(); return nil } }
}
