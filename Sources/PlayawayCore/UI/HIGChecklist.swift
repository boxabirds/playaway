import Foundation

/// The HIG review gate (ui.review.hig_checklist). The release is allowed only when every item is `pass`, or is
/// recorded with an `exception` and a written reason.
///
/// File format (`docs/hig-checklist.md`): every item is ONE line starting with `- [` :
///
///     - [item-id] pass
///     - [item-id] pass: optional note, e.g. which test verifies it
///     - [item-id] fail
///     - [item-id] exception: the written reason this deviation is accepted
///     - [item-id] unmarked
///
/// `item-id` is any text without `]`. The status word is case-insensitive. A line with an item id and no
/// recognised status word is `unmarked`. `exception:` with an empty reason is a fail without exception.
/// The `- [` must be in column 0. Every other line (headings, prose, indented descriptions or examples) is ignored. Who signs off is deliberately not part of
/// the format (open question).
package enum ChecklistStatus: Equatable {
    case pass, fail, exception(reason: String), unmarked
}

package struct ChecklistItem: Equatable {
    package init(id: String, status: ChecklistStatus) {
        self.id = id
        self.status = status
    }
    package let id: String
    package let status: ChecklistStatus
}

package enum ChecklistError: Error, Equatable {
    case fileMissing(String)
    case noItems
    case unmarked(String)
    case failWithoutException(String)
}

package enum HIGChecklistFormat {
    package static let itemPrefix = "- ["
    package static let itemTerminator: Character = "]"
    package static let statusSeparator: Character = ":"
    package static let passWord = "pass"
    package static let failWord = "fail"
    package static let exceptionWord = "exception"
    package static let unmarkedWord = "unmarked"
    package static let defaultPath = "docs/hig-checklist.md"
}

/// Parses the items of a checklist file. Returns nil when the file cannot be read.
package func parseChecklist(at path: String) -> [ChecklistItem]? {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    return parseChecklist(text)
}

package func parseChecklist(_ text: String) -> [ChecklistItem] {
    text.split(whereSeparator: \.isNewline).compactMap { rawLine in
        let line = String(rawLine)  // must start in column 0: indented lines (examples, descriptions) are not items
        guard line.hasPrefix(HIGChecklistFormat.itemPrefix),
              let close = line.firstIndex(of: HIGChecklistFormat.itemTerminator) else { return nil }
        let id = line[line.index(line.startIndex, offsetBy: HIGChecklistFormat.itemPrefix.count)..<close]
            .trimmingCharacters(in: .whitespaces)
        let rest = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return ChecklistItem(id: id, status: status(fromRemainder: rest))
    }
}

private func status(fromRemainder rest: String) -> ChecklistStatus {
    let wordEnd = rest.firstIndex(of: HIGChecklistFormat.statusSeparator) ?? rest.endIndex
    let word = rest[..<wordEnd].trimmingCharacters(in: .whitespaces).lowercased()
    let after = wordEnd < rest.endIndex
        ? rest[rest.index(after: wordEnd)...].trimmingCharacters(in: .whitespaces) : ""
    switch word {
    case HIGChecklistFormat.passWord: return .pass
    case HIGChecklistFormat.failWord: return .fail
    case HIGChecklistFormat.exceptionWord: return after.isEmpty ? .fail : .exception(reason: after)
    default: return .unmarked
    }
}

/// Items that failed but carry a recorded exception reason, for the release record.
package func checklistExceptions(at path: String) -> [(id: String, reason: String)] {
    (parseChecklist(at: path) ?? []).compactMap { item in
        if case .exception(let reason) = item.status { return (item.id, reason) }
        return nil
    }
}

/// Empty result means the checklist passes. Missing file, no items, unmarked items and fails without exception
/// each produce an error naming the path or the item.
package func validateChecklist(at path: String) -> [ChecklistError] {
    guard let items = parseChecklist(at: path) else { return [.fileMissing(path)] }
    guard !items.isEmpty else { return [.noItems] }
    return items.compactMap { item in
        switch item.status {
        case .pass, .exception: return nil
        case .fail: return .failWithoutException(item.id)
        case .unmarked: return .unmarked(item.id)
        }
    }
}

extension ChecklistError {
    package var message: String {
        switch self {
        case .fileMissing(let path): return "checklist file missing: \(path)"
        case .noItems: return "checklist has no items"
        case .unmarked(let id): return "item not marked: \(id)"
        case .failWithoutException(let id): return "item failed with no recorded exception: \(id)"
        }
    }
}

/// Entry point for a release script or a command-line flag. Prints each failure; returns nonzero if any.
@discardableResult
package func runHIGChecklistCheck(path: String = HIGChecklistFormat.defaultPath,
                          output: (String) -> Void = { print($0) }) -> Int32 {
    let errors = validateChecklist(at: path)
    for error in errors { output(error.message) }
    for exception in checklistExceptions(at: path) { output("exception recorded: \(exception.id): \(exception.reason)") }
    return errors.isEmpty ? 0 : 1
}
