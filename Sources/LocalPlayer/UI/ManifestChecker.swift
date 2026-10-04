import Foundation

enum WindowState: String, CaseIterable {
    case idle
    case playing
    case editingPlaylist = "editing_playlist"
    case noticeShown = "notice_shown"
    case untitledEmpty = "untitled_empty"
}

struct ObservedElement: Codable, Equatable {
    let id: String?
    let role: String
}

enum Violation: Equatable, CustomStringConvertible {
    case unrecorded(String, WindowState)
    case unidentified(String, WindowState)
    case stale(String)

    var description: String {
        switch self {
        case .unrecorded(let id, let state): return "unrecorded element '\(id)' is visible in state \(state.rawValue)"
        case .unidentified(let role, let state): return "visible \(role) with no identifier in state \(state.rawValue)"
        case .stale(let id): return "recorded element '\(id)' is visible in no state"
        }
    }
}

/// Pure comparison of what is on screen with what is recorded. All violations are reported together.
enum ManifestChecker {
    static func check(manifest: UIManifest, kind: WindowKind, observed: [WindowState: [ObservedElement]]) -> [Violation] {
        let recorded = Set((manifest.entries[kind] ?? []).map(\.elementID))
        var violations: [Violation] = []
        var visibleAnywhere = Set<String>()
        for state in WindowState.allCases {
            for element in observed[state] ?? [] {
                guard let id = element.id, !id.isEmpty else {
                    violations.append(.unidentified(element.role, state))
                    continue
                }
                visibleAnywhere.insert(id)
                if !recorded.contains(id) { violations.append(.unrecorded(id, state)) }
            }
        }
        for id in recorded.sorted() where !visibleAnywhere.contains(id) { violations.append(.stale(id)) }
        return violations
    }
}
