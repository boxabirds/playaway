# PRD

Playlists are ordinary Mac documents: each opens in its own window, is saved where the person chooses (Documents by default), updates itself in place, and is edited by adding, removing and reordering files.

## Problem

People who keep audio files on their Mac want to group them into lists such as 'Running', 'Dinner' or 'Album I am learning'. Music (formerly iTunes) ties lists to an internal library the person cannot see or move, and other players bury list-making under dozens of options. People are also afraid of losing a carefully ordered list: if an app crashes or the Mac loses power while a list is being saved, the whole list can be gone, and a list that lives only inside an app cannot be put where the person wants it, copied, or backed up. They want to make a list the way they make any other document on a Mac, keep it wherever they like, and trust that it is still there tomorrow.

## Solution

A playlist behaves like any other Mac document. The person chooses New Playlist and an untitled playlist opens in its own window. The first time they save it, the usual Save panel appears, offering the Documents folder by default, and they choose the name and the place. From then on every change is saved into the same file automatically, with no Save button. They can open a playlist from Finder, from the File menu or from Open Recent; if it is already open, its window simply comes to the front. They can rename it the way any document is renamed. Inside a playlist they can add files, remove files and drag files into a different order. A save that is interrupted never damages the last good version, so a playlist is never lost or half-written. Each playlist is an ordinary file the person can see in Finder, copy, move, delete in Finder and keep in iCloud Drive if they want it backed up. Removing a file from a playlist never touches the audio file itself. An attempt to add a file the app cannot play is declined with the same plain 'not supported yet' message used when opening files. The app also keeps a playlist up to date by itself when it refreshes the link to a moved audio file or the person points it at a missing one. Together this gives the person full control of their lists with nothing to learn and nothing to fear.

## User Experience

## Golden path
1. The person chooses New Playlist. A new window opens with an empty, untitled playlist and an invitation to add files.
2. The person drags audio files from Finder into the window, or chooses files to add from a menu item. The files appear in the list in the order added.
3. The person drags a file up or down to put it where they want it. The list shows the new order straight away.
4. The person saves for the first time. The standard Save panel appears with the Documents folder offered; they type a name, optionally choose another place, and confirm. The window title becomes the file name.
5. From now on every change is saved automatically into that file. There is no Save button to press.
6. The person quits the app. Next time they open the playlist from Finder, the File menu or Open Recent, a window shows the files in the same order.

Other actions: Rename changes the playlist's name in the usual document way (from the window title or the File menu); Remove takes a selected file out of the playlist.

## Alternate flows
- **Empty playlist:** a new playlist shows no files and a clear invitation to add some. Playback controls do nothing until it has files.
- **Unsupported file added:** the file is not added. The person sees the same short message used elsewhere, saying the file type is not supported yet and why, and the playlist is unchanged.
- **Last file removed:** the playlist stays, empty.
- **Saving with a name that already exists:** the standard Save panel's own choices apply (replace the existing file or keep both). The app adds no extra naming rules.
- **Save failure:** if a change cannot be saved (for example the disk is full or the folder is read-only), the person is told that the change could not be saved. The last saved version of the playlist is still intact on disk.
- **Opening a playlist that is already open:** its window comes to the front. No second window appears.
- **Closing an untitled playlist that has files in it:** the app behaves as it does for any untitled Mac document. This is provisional; the exact behaviour is an open question below.
- **Deleting a playlist:** the app does not offer this. The person deletes the playlist file in Finder. Audio files are never affected.

## Structure
Each playlist has its own window showing its files in order, with the standard window title naming the playlist. There is no main window and no list of playlists. New Playlist, Open, Open Recent, Rename, Add Files and Remove are reachable from menus; reordering is done by dragging a file within the list.

## Behaviour
- After the first save, changes are saved automatically; there is no Save button.
- The order shown is always the saved order.
- Removing a file from a playlist never asks the person to confirm, because it never deletes audio files.
- The app may update a saved playlist by itself when a link to a moved audio file is refreshed or a missing file is located. The person's files, names, order and settings are not changed by this.

## Explicit non-behaviours
- Does not copy, move or modify the audio files that a playlist refers to.
- Does not keep playlists inside a hidden library; each is its own file in a place the person chose.
- Does not offer a Delete Playlist action.
- Does not show a list of all playlists.
- Does not back playlists up or sync them; that is the person's choice via iCloud Drive.
- Does not sort automatically; the person's order is kept.

## Acceptance Criteria

A non-technical person can verify each of these by hand:
1. Choose New Playlist: a window with an empty, untitled playlist opens.
2. Drag three different mp3, wav and m4a files in: all three appear, in the order dropped.
3. Drag the third file to the top: the list shows it first.
4. Save: the Save panel offers the Documents folder. Name it 'Dinner' and confirm: the window title shows 'Dinner'.
5. Quit and relaunch the app, then open 'Dinner' from Finder: the same order is shown. Open it again: the existing window comes to the front and no second window appears.
6. Change the order again and quit without pressing anything: reopen and the new order is there.
7. Rename the playlist to 'Supper': the new name shows in the window title and in Finder.
8. Remove the middle file: it disappears from the list; find it in Finder and it is still there.
9. Drag a .flac file in: it is not added and a 'not supported yet' message appears.
10. Find the playlist in Finder: it is a single file you can copy to iCloud Drive, and Finder shows it as a playlist that opens in this app.
11. Make a change while the disk is full or the folder is read-only: a 'could not be saved' message appears, and after relaunch the playlist shows its previous contents.
12. Move an audio file to another folder, open the playlist, then quit and reopen it: the playlist still plays the moved file, and you did nothing to update it.

## Create a playlist

> Anchor: `prd.playlist.create`

WHEN the person chooses New Playlist THE SYSTEM SHALL open a new untitled empty playlist in its own window, ready to receive files.

## First save uses the standard Save panel

> Anchor: `prd.playlist.save_location`

WHEN the person saves a new playlist for the first time THE SYSTEM SHALL show the standard Save panel offering the Documents folder by default and let the person choose the name and the place.

## Changes are saved automatically

> Anchor: `prd.playlist.autosave`

WHEN the person changes a playlist that has been saved THE SYSTEM SHALL save the change into the same file automatically, without a Save button being pressed.

## Open a playlist

> Anchor: `prd.playlist.open`

WHEN the person opens a playlist from Finder, the File menu or Open Recent THE SYSTEM SHALL show it in its own window with the files in the order they were last saved.

## An open playlist is not opened twice

> Anchor: `prd.playlist.open_once`

WHILE a playlist is already open WHEN the person opens that same playlist again THE SYSTEM SHALL bring its existing window to the front and SHALL NOT open a second window for it.

## Rename a playlist

> Anchor: `prd.playlist.rename`

WHEN the person renames a playlist in the usual document way THE SYSTEM SHALL show and save the new name without changing the files in the playlist or their order.

## Add files to a playlist

> Anchor: `prd.playlist.add`

WHEN the person adds supported audio files to a playlist THE SYSTEM SHALL include those files in the playlist and save the change.

## Remove files from a playlist

> Anchor: `prd.playlist.remove`

WHEN the person removes a file from a playlist THE SYSTEM SHALL take that file out of the playlist and save the change.

## Reorder files in a playlist

> Anchor: `prd.playlist.reorder`

WHEN the person moves a file to a new position in a playlist THE SYSTEM SHALL show the files in the new order and save that order.

## Unsupported files are declined

> Anchor: `prd.playlist.reject_unsupported`

WHEN the person tries to add a file whose type is not supported THE SYSTEM SHALL NOT add it, SHALL display a message saying the file type is not supported yet and why, and SHALL leave the playlist unchanged.

## Changes persist across launches

> Anchor: `prd.playlist.persist`

WHEN the person quits and relaunches the app and opens a saved playlist THE SYSTEM SHALL show the files, order and name it had when it was last changed.

## Failed or interrupted saves are safe

> Anchor: `prd.playlist.save_safe`

IF a playlist cannot be saved, or saving is interrupted, THEN THE SYSTEM SHALL NOT lose or damage the last successfully saved version, and SHALL tell the person that the change could not be saved.

## The app keeps a playlist up to date by itself

> Anchor: `prd.playlist.self_update`

WHEN the app refreshes the link to a moved audio file, or the person points it at a missing audio file, THE SYSTEM SHALL save the updated link into the playlist file without any action by the person, and SHALL NOT change the playlist's name, files, order or settings.

## Removing a file never changes the audio file

> Anchor: `prd.playlist.audio_untouched`

IF the person removes a file from a playlist THEN THE SYSTEM SHALL NOT delete, move or modify the audio file itself.

## Each playlist is an ordinary file

> Anchor: `prd.playlist.own_file`

THE SYSTEM SHALL store each playlist as its own file, in the place the person chose, that the person can see in Finder, copy, delete in Finder and place in iCloud Drive.

## Finder recognises playlists

> Anchor: `prd.playlist.doctype`

THE SYSTEM SHALL identify its playlist files to macOS so that Finder shows them as playlists belonging to the app and opens them in the app.

## Constraints

- Runs on macOS 26 and later.
- Playlist files must be safe to keep in iCloud Drive and to copy between Macs; the app does not itself back up or sync them.
- Every action in this story except system document actions must also be controllable by AppleScript (covered in the AppleScript story).
- Only mp3, wav and m4a files can be added.
- The app is a document-based Mac app: one window per open playlist, and no main window.

## Out of scope

- Playing a playlist, shuffle and repeat (separate story).
- Files that have been moved or deleted after being added, and how the app finds them (separate missing-files story). This story only requires that the resulting updated link is saved.
- What the playlist file looks like inside and its file extension: proposed as a versioned JSON file with the extension .lplaylist, not decided.
- Deleting a playlist: the app does not offer it; the person does it in Finder.
- Duplicate files within one playlist: not decided.
- What the person sees when a playlist file is damaged or was made by a newer version of the app: not decided.
- Importing or exporting playlists for other players.
- Opening a playlist by double-clicking it in Finder so that it starts playing (separate story).
- Playback controls, which window plays a single opened audio file, and volume (separate stories).

## Open questions

These are recorded, not decided:
1. What exactly happens to an untitled playlist that has files in it when its window is closed or the app quits. The working assumption is the standard behaviour of any untitled Mac document.
2. Which window hosts playback when a single audio file is opened (decided in the playback stories, not here).
3. Whether the same file may appear twice in one playlist.

