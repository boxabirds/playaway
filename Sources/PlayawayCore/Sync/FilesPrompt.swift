import Foundation

/// What the person chose in the Files dialog. `doNothing` is the internal name; its label is "Add Without Syncing".
package enum FilesChoice: Equatable {
    case moveToICloud
    case copyToICloud
    case doNothing
}

package enum FilesButtonRole: Equatable {
    case destructive
    case defaultAction
    case plain
}

package struct FilesButton: Equatable {
    package let choice: FilesChoice
    package let label: String
    package let role: FilesButtonRole
}

/// The Files dialog, defined once for every way of adding songs on every platform. The wording is the owner's.
package enum FilesPrompt {
    package static let title = "Sync with iCloud: Files"
    package static let message = "This is an iCloud playlist, and Some of the files in your playlist are not in iCloud."
    package static let buttons = [
        FilesButton(choice: .moveToICloud, label: "Move to iCloud", role: .destructive),
        FilesButton(choice: .copyToICloud, label: "Copy to iCloud", role: .defaultAction),
        FilesButton(choice: .doNothing, label: "Add Without Syncing", role: .plain),
    ]

    /// Dismissing the dialog without choosing counts as Add Without Syncing: nothing is moved or copied.
    package static let dismissalChoice = FilesChoice.doNothing

    /// The report after a move in which some songs were copied instead. Nil when none were.
    package static func copiedInsteadReport(_ count: Int) -> String? {
        count >= 1 ? "\(count) files were on separate volumes or read only and copies were placed on iCloud, NOT moved" : nil
    }

    /// The plain message naming songs that could not be handled. Nil when there were none.
    package static func failureMessage(_ failures: [TransferFailure]) -> String? {
        guard !failures.isEmpty else { return nil }
        let names = failures.map(\.fileName).joined(separator: ", ")
        return failures.count == 1 ? "This song could not be moved to iCloud and was left where it was: \(names)"
                                   : "These songs could not be moved to iCloud and were left where they were: \(names)"
    }
}

package protocol FilesPromptPresenting: AnyObject {
    func askFilesChoice() async -> FilesChoice
    func show(message: String) async
}
