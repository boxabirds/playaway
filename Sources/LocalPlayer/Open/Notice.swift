import Foundation

/// Messages the app shows to the person. Later stories add cases here.
enum Notice: Equatable {
    case unsupported(UnsupportedReason)
    case saveFailed(String)

    static let dismissTitle = "Dismiss"
    static let supportedTypesSentence = "LocalPlayer currently plays MP3, WAV and M4A files."

    var title: String {
        switch self {
        case .unsupported: return "This file type is not supported yet."
        case .saveFailed: return "The change could not be saved."
        }
    }

    var detail: String {
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
        }
    }

    var fullText: String { "\(title)\n\(detail)" }
}
