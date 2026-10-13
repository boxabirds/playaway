import Foundation

/// Where this playlist stands when its start button is pressed.
package enum PlaylistSessionState: Equatable {
    case songUnderWay(isPlaying: Bool)   // a song of this playlist is playing or paused
    case noSongUnderWay
}

package enum StartDecision: Equatable {
    case toggleCurrentSong
    case startShuffled(firstIndex: Int)  // a random song of this playlist; play on in shuffled order, this playlist only
    case startInOrder                    // from the first song, in listed order
    case nothingToStart                  // an empty playlist starts nothing and stops nothing
}

/// What the start button does. Never changes the Shuffle toggle: it only reads it.
package func startDecision(session: PlaylistSessionState, shuffleOn: Bool, songCount: Int,
                           random: inout some RandomNumberGenerator) -> StartDecision {
    if case .songUnderWay = session { return .toggleCurrentSong }
    guard songCount > 0 else { return .nothingToStart }
    return shuffleOn ? .startShuffled(firstIndex: Int.random(in: 0..<songCount, using: &random)) : .startInOrder
}

package enum StartButtonIcon: Equatable { case play, pause }

/// The button shows pause while this playlist's song plays, and play otherwise (not current, paused or idle).
package func startButtonIcon(session: PlaylistSessionState) -> StartButtonIcon {
    if case .songUnderWay(isPlaying: true) = session { return .pause }
    return .play
}
