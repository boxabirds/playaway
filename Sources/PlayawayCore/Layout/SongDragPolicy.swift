import Foundation

/// What a dragged song carries. Its id is always carried, for reordering inside the list. Its file's address is carried only
/// where something can take it: the iPad's sidebar of playlists, and other apps beside this one. On the iPhone nothing in
/// the app can take a file, but the song list's own page accepts dropped files (to add them), so a song that carried its
/// file address could be claimed by that drop instead of the list's reorder: the row was lifted without being seen and
/// then flew back. Owner's report from a real iPhone, which the iPad does not show; not reproduced in the simulator.
public enum SongDragPolicy {
    public static func offersFileURL(isPad: Bool) -> Bool { isPad }
}
