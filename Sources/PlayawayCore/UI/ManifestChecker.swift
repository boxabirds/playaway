import Foundation

package enum WindowState: String, CaseIterable {
    case idle
    case playing
    case editingPlaylist = "editing_playlist"
    case noticeShown = "notice_shown"
    case untitledEmpty = "untitled_empty"
}

package struct ObservedElement: Codable, Equatable {
    package init(id: String?, role: String) {
        self.id = id
        self.role = role
    }
    package let id: String?
    package let role: String
}

package enum Violation: Equatable, CustomStringConvertible {
    case unrecorded(String, WindowState)
    case unidentified(String, WindowState)
    case stale(String)

    package var description: String {
        switch self {
        case .unrecorded(let id, let state): return "unrecorded element '\(id)' is visible in state \(state.rawValue)"
        case .unidentified(let role, let state): return "visible \(role) with no identifier in state \(state.rawValue)"
        case .stale(let id): return "recorded element '\(id)' is visible in no state"
        }
    }
}

/// Pure comparison of what is on screen with what is recorded. All violations are reported together.
package enum ManifestChecker {
    package static func check(manifest: UIManifest, kind: WindowKind, observed: [WindowState: [ObservedElement]]) -> [Violation] {
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
