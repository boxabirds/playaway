# PRD

Playlists survive moved files, clearly mark deleted ones, and let the person reconnect a whole folder of missing tracks in one step.

## Problem

People reorganise their music folders. They move albums to an external drive, tidy up a downloads folder, or delete files they no longer want. Playlists that point at files by their exact location silently break the moment anything moves. The person then discovers the break by pressing play and getting nothing, with no indication of which tracks are affected or why. Fixing a playlist with fifty broken tracks one by one is so tedious that people abandon the playlist.

## Solution

Playlists keep working when files are moved: the app still finds the file and plays it, with no action from the person, and the playlist quietly remembers the file's new home as part of its normal saving. When a file really is gone (deleted, or on a drive that is not connected), its track stays in the playlist but is greyed out and cannot be played, so the person can see at a glance exactly which tracks are affected. When a playlist plays on its own it skips such a track, marks it with a hazard icon so the person can see what was skipped, and carries on, so the music does not stop. If the person double-clicks a missing track to play it, nothing plays and the track gets the same hazard icon, so the person learns at once why. On a greyed-out track the person can choose Locate and point at the file's new home. The app then looks in that same folder for every other missing track of that playlist and reconnects the ones it finds, so an entire moved album is repaired with a single choice. Tracks it cannot find stay greyed out and are never guessed at. The person can then use the playlist again without fixing fifty tracks one by one.

## User Experience

Each playlist is its own document with its own window, and the tracks are shown in that window. Everything below happens in the window of the playlist the person has opened.

## Golden path
1. The person moves an album folder to another place on their Mac.
2. They open a playlist that contains tracks from that album. The tracks look normal and play normally. Nothing is asked of them.
3. The playlist remembers where the files now are, as part of its normal saving, so the next opening is just as smooth. The person sees no extra step and no prompt for this.

## Missing-file path
1. The person deleted a file, or the drive holding it is not connected. They open the playlist.
2. That track appears greyed out in the list. Other tracks in the playlist are unaffected.
3. If the person double-clicks the greyed-out track to play it, nothing plays and a hazard icon appears next to the track. No dialog or message appears.
4. The person selects the greyed-out track and chooses Locate on that track's row. A standard file chooser opens.
5. They pick the file. The track becomes normal and playable, and its hazard icon, if it had one, goes away.
6. The app then checks the folder holding the chosen file. Every other greyed-out track of the same playlist whose file name is in that folder becomes normal and playable too.
7. The playlist records the repaired tracks as part of its normal saving, like any other change the person makes to it.

## Automatic play-through
- When a playlist plays on its own and reaches a missing track, that track is skipped, it gets a hazard icon, and the next track plays. No message or dialog is shown. The hazard icon is the same one used for a track that cannot be read, and it shows only during the current session.

## Alternate flows
- **Person cancels the file chooser:** nothing changes; the track stays greyed out.
- **The folder has none of the other missing files:** only the chosen track is repaired; the others stay greyed out and nothing is shown to say so.
- **A drive is reconnected later:** the next time the playlist is opened its tracks are found again and look normal.
- **Playlist with no missing tracks:** looks and behaves exactly as before; no extra elements appear.
- **Playlist where every track is missing:** all rows are greyed out. Double-clicking a row plays nothing and marks that row. Automatic play-through marks each missing track it reaches and, finding nothing playable, stops.

## Empty and error states
- Empty state: a playlist with no tracks has nothing to mark.
- Error state: a track the app cannot find is greyed out. When the person tries to play it, or play-through skips it, it also shows the hazard icon. No pop-up is shown, whether the playlist is opened, a play is attempted or a track is skipped.
- If the playlist cannot be saved after a repair, the person gets the app's standard could-not-be-saved message from the playlist story. The repair still shows on screen for this session.

## Structure
- A greyed-out look for missing tracks, in the playlist's own window.
- A hazard icon on a missing track that was skipped or that the person tried to play.
- A Locate action available on a missing track's row only (context menu on the track).
- No Locate action on tracks that are present.

## Behaviour
- Missing tracks cannot be played by the person or by automatic play-through.
- Choosing Locate on a track updates only that playlist and clears that track's hazard icon.
- Matching is by file name only.
- Following a moved file or repairing a track counts as a change to the playlist and is saved the same way as any other change.

## Explicit non-behaviours
- Does not delete a missing track from the playlist automatically.
- Does not move, rename, copy or change any of the person's audio files while searching.
- Does not search outside the single folder of the located file.
- Does not guess when file names are ambiguous; this case is not specified yet.
- Does not show a warning dialog when a playlist is opened with missing tracks, when the person tries to play one, or when play-through skips one.
- Does not offer a way to delete a playlist; that is done in Finder.

## Moved files are still found

> Anchor: `prd.missing.track`

WHEN a file that is in a playlist has been moved to another place on the same Mac and the person opens that playlist THE SYSTEM SHALL still find the file and play it without any action from the person, and SHALL keep the playlist pointing at the file's new place as part of the playlist's normal saving.

## Missing tracks are greyed out

> Anchor: `prd.missing.grey`

WHILE a track's file has been deleted or cannot be found THE SYSTEM SHALL show that track greyed out in the playlist.

## Missing tracks cannot be played

> Anchor: `prd.missing.unplayable`

WHILE a track's file has been deleted or cannot be found THE SYSTEM SHALL NOT play that track.

## Automatic play-through skips and marks missing tracks

> Anchor: `prd.missing.autoskip`

WHEN automatic play-through reaches a missing track THE SYSTEM SHALL skip that track, mark it with a hazard icon, and continue with the next track.

## Playing a missing track by double-click is refused and marked

> Anchor: `prd.missing.playmarked`

WHEN the person double-clicks a missing track to play it THE SYSTEM SHALL NOT play it, SHALL mark it with a hazard icon, and SHALL NOT show a dialog.

## Locate a missing file

> Anchor: `prd.missing.locate`

WHEN the person chooses Locate on a missing track and picks a file THE SYSTEM SHALL make that track use the picked file, make it playable, remove its hazard icon, and keep the playlist pointing at that file as part of the playlist's normal saving.

## Reconnect other missing tracks from the same folder

> Anchor: `prd.missing.folder`

WHEN the person has located a missing track THE SYSTEM SHALL look in the folder of the located file for other missing tracks of the same playlist and reconnect each one whose file name matches a file in that folder.

## Unmatched tracks stay missing

> Anchor: `prd.missing.nonmatch`

IF a missing track's file name is not found in the folder of the located file THEN THE SYSTEM SHALL NOT change that track and SHALL leave it greyed out.

## Searching never changes audio files

> Anchor: `prd.missing.untouched`

IF the system searches a folder for missing tracks THEN THE SYSTEM SHALL NOT move, rename, copy or modify any file in that folder.

## Acceptance criteria

A non-technical person can verify each of these by hand, using a playlist of five tracks from one album folder.
1. Move the album folder to another place on the Mac and open the playlist: all five tracks look normal and play.
2. Delete one file and open the playlist: that track is greyed out; the other four play.
3. Double-click the greyed-out track: nothing plays, a hazard icon appears next to it, and no dialog appears.
4. Disconnect the drive holding the files and open the playlist: the affected tracks are greyed out. Reconnect the drive and open the playlist again: they look normal.
5. Choose Locate on a greyed-out track, pick the file: that track becomes normal and plays, and its hazard icon, if any, is gone.
6. Delete two files, put both back in one new folder, choose Locate on one of them and pick it: both tracks become normal in one step. A third missing track whose file is not in that folder stays greyed out.
7. Choose Locate and cancel the file chooser: nothing changes.
8. Let the playlist play on its own with one greyed-out track in the middle: that track is skipped, it shows a hazard icon, the next one plays, and no message or dialog appears.
9. After any of the repairs above, quit and reopen the playlist: the repaired tracks are still normal.
10. Find the audio files in Finder after a Locate: none has been moved, renamed or changed.

## Constraints

- Runs on macOS 26 and later; the app is not sandboxed.
- Matching of missing tracks is by file name only.
- Following moved files may use any mechanism that is as reliable as the system's own file-following facility; the choice is left to the implementer and is described in the technical design, not here.
- Each playlist is an ordinary document in a location the person chose. A repaired or refreshed track is saved into that playlist the same way any other change to it is saved; the playlist management story owns saving.
- The hazard icon is the one the playlist playback story shows for an unreadable track, and it appears only for the current session.
- Every action here must also be available through AppleScript (covered by the AppleScript story).
- Backing up playlists is the person's responsibility.

## Out of scope

- Two or more files with the same file name in the searched folder (accepted gap; behaviour not specified).
- Matching by anything other than file name (content, tags, length).
- Searching sub-folders or other locations.
- Following a file that has been renamed.
- Removing missing tracks from a playlist in bulk.
- Warning dialogs or notifications about missing tracks.
- Deleting a playlist: it is not an app feature; the person does it in Finder.
- The playlist file format itself, and how a playlist is saved (covered by the playlist management story).
- Drawing the hazard icon and the rule for a track that is present but cannot be read (covered by the playlist playback story). A missing track and an unreadable track are different conditions that share the same hazard icon.

