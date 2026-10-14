import Foundation

/// The things VoiceOver offers on a song row in place of swiping and dragging.
package enum SongRowAction: Equatable {
    case moveUp
    case moveDown
    case remove
}

/// Move up is offered unless the song is first, move down unless it is last, remove always.
package func songRowActions(index: Int, count: Int) -> [SongRowAction] {
    guard index >= 0, index < count else { return [] }
    var actions: [SongRowAction] = []
    if index > 0 { actions.append(.moveUp) }
    if index < count - 1 { actions.append(.moveDown) }
    actions.append(.remove)
    return actions
}
