import PlayawayCore
import Foundation

/// Stable error numbers returned to scripts. Accepted by the owner for now; they may change until the first release.
enum ScriptError {
    static let noSuchPlaylist = 1001
    static let nothingPlaying = 1002
    static let unsupportedFile = 1003
    static let fileNotFound = 1004
    static let invalidParameter = 1005
    static let noSuchTrack = 1006
    static let locateFailed = 1007
    static let notReady = 1008
    /// Owner decision 2026-10-13: a command that needs iCloud while iCloud is unavailable.
    static let iCloudUnavailable = 1009
    /// Proposal: turning sync on could not move the playlist (nothing changed).
    static let syncFailed = 1010
    /// A scripted play whose download from iCloud failed (number and wording a proposal; PRD story 22 open question 10).
    static let downloadFailed = 1011
}

/// A refused command: a number and a plain-language message. A refused command changes nothing.
struct ScriptFailure: Error, Equatable {
    let number: Int
    let message: String

    static func noOpenPlaylist(named name: String) -> ScriptFailure {
        ScriptFailure(number: ScriptError.noSuchPlaylist, message: "No open playlist named \(name)")
    }
    static let nothingPlaying = ScriptFailure(number: ScriptError.nothingPlaying, message: "Nothing is playing.")
    static func unsupported(_ reason: UnsupportedReason) -> ScriptFailure {
        ScriptFailure(number: ScriptError.unsupportedFile, message: Notice.unsupported(reason).fullText)
    }
    static func notFound(_ path: String) -> ScriptFailure {
        ScriptFailure(number: ScriptError.fileNotFound, message: "No file was found at \(path).")
    }
    static func invalid(_ message: String) -> ScriptFailure {
        ScriptFailure(number: ScriptError.invalidParameter, message: message)
    }
    static func noSuchTrack(_ position: Int, count: Int) -> ScriptFailure {
        ScriptFailure(number: ScriptError.noSuchTrack, message: "There is no track \(position); the playlist has \(count).")
    }
    static func locateFailed(_ message: String) -> ScriptFailure {
        ScriptFailure(number: ScriptError.locateFailed, message: message)
    }
    static let notReady = ScriptFailure(number: ScriptError.notReady, message: "The app is not ready yet.")
    static let iCloudUnavailable = ScriptFailure(number: ScriptError.iCloudUnavailable,
                                                 message: "iCloud unavailable: \(ICloudAvailability.unavailableReason)")
    static func syncFailed(_ message: String) -> ScriptFailure { ScriptFailure(number: ScriptError.syncFailed, message: message) }
    static func downloadFailed(_ name: String) -> ScriptFailure {
        ScriptFailure(number: ScriptError.downloadFailed, message: "\(name) could not be downloaded from iCloud, so it was not played.")
    }
}

extension NSScriptCommand {
    /// Records a refusal on the command and returns nil, as script commands must.
    func fail(_ failure: ScriptFailure) -> Any? {
        scriptErrorNumber = failure.number
        scriptErrorString = failure.message
        return nil
    }
}
