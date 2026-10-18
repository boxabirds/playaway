import Foundation

/// Messages the app shows to the person. Later stories add cases here.
package enum Notice: Equatable {
    case unsupported(UnsupportedReason)
    case saveFailed(String)
    /// Turning iCloud sync on could not move the playlist; the reason is for the person.
    case syncFailed(String)
    /// A song added on another device that cannot be found here (story 42): what happened and what to do.
    case addedElsewhere

    package static let dismissTitle = "Dismiss"
    package static let supportedTypesSentence = "Playaway currently plays MP3, WAV and M4A files."

    package var title: String {
        switch self {
        case .unsupported: return "This file type is not supported yet."
        case .saveFailed: return "The change could not be saved."
        case .syncFailed: return "The playlist could not be moved to iCloud."
        case .addedElsewhere: return "This song is on another device."
        }
    }

    package var detail: String {
        switch self {
        case .unsupported(let reason):
            switch reason {
            case .unknownType(let description):
                return "The file is a \(description) file. \(Self.supportedTypesSentence)"
            case .fileNotReadable:
                return "The file could not be read, so its type could not be checked. \(Self.supportedTypesSentence)"
            }
        case .saveFailed(let reason):
            return reason.isEmpty ? "The last saved version is still intact." : "\(reason) The last saved version is still intact."
        case .addedElsewhere: return addedElsewhereMessage
        case .syncFailed(let reason):
            return reason.isEmpty ? "The playlist is still where it was." : "\(reason) The playlist is still where it was."
        }
    }

    package var fullText: String { "\(title)\n\(detail)" }
}
