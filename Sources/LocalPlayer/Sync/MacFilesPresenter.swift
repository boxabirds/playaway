import PlayawayCore
import AppKit

/// The Files dialog as a sheet: Copy to iCloud is the default (rightmost), Move to iCloud is destructive, Add Without
/// Syncing is the escape. The report box and failure messages are one-button sheets.
@MainActor
final class MacFilesPresenter: FilesPromptPresenting {
    private weak var window: NSWindow?
    init(window: NSWindow?) { self.window = window }

    func askFilesChoice() async -> FilesChoice {
        let alert = NSAlert()
        alert.messageText = FilesPrompt.title
        alert.informativeText = FilesPrompt.message
        // NSAlert's first button is the default; the order here places Copy rightmost, Move beside it, then the escape.
        let ordered = FilesPrompt.buttons.sorted { a, _ in a.role == .defaultAction }
        for button in ordered {
            let made = alert.addButton(withTitle: button.label)
            if button.role == .destructive { made.hasDestructiveAction = true }
            if button.role == .plain { made.keyEquivalent = "\u{1b}" }
        }
        let response: NSApplication.ModalResponse = if let window { await alert.beginSheetModal(for: window) } else { alert.runModal() }
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return ordered.indices.contains(index) ? ordered[index].choice : FilesPrompt.dismissalChoice
    }

    func show(message: String) async {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        if let window { _ = await alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}

/// A test seam's answers for the Files question and the messages that follow.
final class ClosureFilesPresenter: FilesPromptPresenting {
    private let ask: () async -> FilesChoice
    private let shown: (String) -> Void
    init(ask: @escaping () async -> FilesChoice, shown: @escaping (String) -> Void) { self.ask = ask; self.shown = shown }
    func askFilesChoice() async -> FilesChoice { await ask() }
    func show(message: String) async { shown(message) }
}

/// A script's Files answer, given in advance; without one the songs are added without syncing (story 22, open
/// question 1: a script must never wait on a dialog). Messages go to the script's result through `messages`.
final class ScriptedFilesPresenter: FilesPromptPresenting {
    private let answer: FilesChoice
    private(set) var messages: [String] = []
    init(_ answer: FilesChoice?) { self.answer = answer ?? FilesPrompt.dismissalChoice }
    func askFilesChoice() async -> FilesChoice { answer }
    func show(message: String) async { messages.append(message) }
}
