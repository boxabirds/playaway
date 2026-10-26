import Foundation

/// Choose Replacement is offered on a song that was on this device and is gone (renamed, moved, deleted) and that has a
/// portable location, because the chosen file is remembered per device under that location. A locked or elsewhere song
/// has its own way forward, and a song that is not missing needs none.
package func offersReplacement(_ kind: UnfoundKind?, for reference: TrackReference) -> Bool {
    kind == .gone && reference.portableLocation != nil
}

/// The name of the file a song was found as, when it is not the name the playlist stored (letter case aside); nil when
/// nothing was found or the name is the same.
package func foundUnderNewName(stored: String, found: URL?) -> String? {
    guard let name = found?.lastPathComponent, name.caseInsensitiveCompare(stored) != .orderedSame else { return nil }
    return name
}
