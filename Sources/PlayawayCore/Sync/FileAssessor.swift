import Foundation

package enum TrackICloudClass: Equatable {
    case alreadyInICloud
    case needsTransfer
    case missingFile
}

package struct AssessmentResult: Equatable {
    package let classes: [TrackICloudClass]
    package init(classes: [TrackICloudClass]) { self.classes = classes }

    /// The Files question is asked only when at least one song would have to be moved or copied.
    package var needsPrompt: Bool { classes.contains(.needsTransfer) }
}

/// Sorts a playlist's songs into: already in iCloud (anywhere in iCloud Drive), in need of a transfer, or missing. Read-only.
package struct FileAssessor {
    private let isUbiquitous: (URL) -> Bool?
    private let fileExists: (URL) -> Bool

    /// `isUbiquitous` is the system's answer for a file: true for an iCloud Drive file, nil when it cannot be asked.
    package init(isUbiquitous: @escaping (URL) -> Bool?,
                 fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        self.isUbiquitous = isUbiquitous
        self.fileExists = fileExists
    }

    /// A nil address means the song's file could not be found at all. A location that cannot be determined counts as
    /// needing a transfer, but the caller never plans one while iCloud is unavailable.
    package func assess(_ files: [URL?]) -> AssessmentResult {
        AssessmentResult(classes: files.map { file in
            guard let file, fileExists(file) else { return .missingFile }
            return iCloudAnswer(isUbiquitous: isUbiquitous(file)) == .inICloud ? .alreadyInICloud : .needsTransfer
        })
    }
}
