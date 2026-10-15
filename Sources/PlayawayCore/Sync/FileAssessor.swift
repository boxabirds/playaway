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

/// Sorts a playlist's songs into: already in iCloud, in need of a transfer, or missing. Read-only.
package struct FileAssessor {
    private let root: URL?
    private let fileExists: (URL) -> Bool

    package init(root: URL?, fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        self.root = root
        self.fileExists = fileExists
    }

    /// A nil address means the song's file could not be found at all. A location that cannot be determined counts as
    /// needing a transfer, but the caller never plans one while iCloud is unavailable.
    package func assess(_ files: [URL?]) -> AssessmentResult {
        AssessmentResult(classes: files.map { file in
            guard let file, fileExists(file) else { return .missingFile }
            return locationAnswer(of: file, root: root) == .insideContainer ? .alreadyInICloud : .needsTransfer
        })
    }
}
