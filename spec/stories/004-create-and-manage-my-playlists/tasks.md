# Tasks

| # | Title | Status | Type | Implements |
|---|-------|--------|------|------------|
| 1 | Implement PlaylistModel edits (add, remove, reorder, reject unsupported) over Playlist and Track | proposed | implementation | playlist.model.edit |
| 2 | Implement PlaylistStore.save with atomic replace, fault-injection seam and self-update writes | proposed | implementation | playlist.store.save |
| 3 | Implement PlaylistStore.load with corrupt and version handling | proposed | implementation | playlist.store.load |
| 4 | Implement PlaylistDocument: new untitled playlist, open once, first save in Documents, autosave, rename | proposed | implementation | playlist.document.lifecycle |
| 5 | Implement the playlist window view and editor controller (add, remove, reorder, notices) | proposed | implementation | playlist.ui.editor |
| 6 | Unit tests: playlist edit matrix (operation x size x position) | proposed | test:unit | playlist.model.edit |
| 7 | Unit tests: playlist encode and decode round trips | proposed | test:unit | playlist.store.save |
| 8 | Integration tests: atomic save under faults and interruption | proposed | test:integration | playlist.store.save |
| 9 | Unit tests: playlist load error classes | proposed | test:unit | playlist.store.load |
| 10 | Integration tests: load from the real file system including missing audio | proposed | test:integration | playlist.store.load |
| 12 | Integration tests: document lifecycle (new, first save, open once, rename, autosave) with stub panels | proposed | test:integration | playlist.document.lifecycle |
| 13 | Integration tests: editor actions, notices and save failure in a playlist window | proposed | test:integration | playlist.ui.editor |
| 14 | E2E tests: playlist document workflows in the built app (Save panel, relaunch, rename, open once, kill, self-update) | proposed | test:e2e | playlist.document.lifecycle |
| 15 | Declare and export the playlist document type (proposed com.localplayer.playlist, .lplaylist) | proposed | implementation | playlist.doctype.declare |
| 16 | Integration tests: built bundle declares the playlist type plus exactly the three audio types | proposed | test:integration | playlist.doctype.declare |
| 17 | E2E tests: editing in the real window (remove, unsupported drop, read-only save failure, no delete menu) | proposed | test:e2e | playlist.ui.editor |

## Details

### 1. Implement PlaylistModel edits (add, remove, reorder, reject unsupported) over Playlist and Track

Implement Track{id: UUID, reference: TrackReference} and Playlist{tracks: [Track]} (name is the file name, not stored) with adding/removing/moving as value-type edits per the design. TrackReference is owned by the missing-files story: consume it, do not redefine it. Add classifies with open.format.classify, appends supported files in the order given as new Tracks, and returns rejected URLs with reasons; a URL that cannot produce a reference is rejected with fileNotReadable. Out-of-range indexes throw indexOutOfRange and leave the playlist unchanged. Never touch audio files. Duplicate files: undecided, do not add rules. Verify with TC-01 to TC-18 and TC-90.

### 2. Implement PlaylistStore.save with atomic replace, fault-injection seam and self-update writes

Implement save(_:to:) as: encode (proposed versioned JSON, tracks with id and reference, name NOT stored), write a temp file in the destination folder, swap in with replace-item under file coordination. Any failure before the swap leaves the destination byte-identical and removes the temp; return writeFailed(reason). The same save carries refreshed or located track references written through the document autosave (self-update): only the changed reference differs. Never create a hidden library. Add a fault-injection seam (disk full, read-only, interruption). Verify with TC-20 to TC-29, TC-35, TC-60 to TC-63, TC-92 and TC-98.

### 3. Implement PlaylistStore.load with corrupt and version handling

Implement load(from:) returning loaded(Playlist) in saved order, or notFound, corrupt (unparseable, truncated, 0-byte) or unsupportedVersion(n). Unknown future fields in a same-version file are ignored. A track whose audio file is missing is returned, not an error. Read-only, never changes the file. The playlist name is the file name. Verify with TC-20 to TC-22, TC-30 to TC-34, TC-48.

### 4. Implement PlaylistDocument: new untitled playlist, open once, first save in Documents, autosave, rename

Implement PlaylistDocument as an NSDocument subclass with autosaving in place, reading and writing through PlaylistStoring, conforming to the missing-files story's PlaylistDocumentEditing (playlist and apply(_:toTrack:)). New Playlist creates one untitled document in its own window and writes no file until the first save. prepareSavePanel starts in the user's Documents folder; the person picks name and place; cancel leaves it untitled. After a file exists every change is autosaved into it with no Save button. One document and window per file URL (opening it again brings the window forward); different URLs get separate windows; no main window and no playlist list. Rename is the standard document rename; failures show Notice.saveFailed (provisional wording) and keep the old name. apply(_ updatedReference:, toTrack:) replaces only that track's reference and marks the document changed so autosave writes it; a track id not in the playlist changes nothing; several calls in a row produce one autosave write. No Delete Playlist. Untitled close/quit behaviour is the framework default (open question). Verify with TC-40 to TC-54, TC-93, TC-94, TC-96, TC-97.

### 5. Implement the playlist window view and editor controller (add, remove, reorder, notices)

Implement the in-window editing only (no playlist list, no delete): Add Files from the menu or a Finder drop, Remove on the selected row, drag a row to reorder. PlaylistView lists the playlist's tracks using story 5's PlaylistTrackRow for each row (greyed look, Locate, and story 2's hazard icon); this task owns the list and editing, not the row appearance. Each action calls PlaylistModel then marks the document changed so autosave writes it. Unsupported files show NoticePresenting.show(Notice.unsupported(reason)) with the supported types named; failed saves show Notice.saveFailed. Expose every action as a controller method so the AppleScript story reuses the code path. Verify with TC-80 to TC-85, TC-91.

### 6. Unit tests: playlist edit matrix (operation x size x position)

Implement TC-01 to TC-18: the operation x size x position matrix, including out-of-range errors, unchanged playlists on error, order of the rest kept, and TC-18 (every Track keeps its id and reference). Positive, negative and boundary cases; real encoded fixtures for the URLs added.

### 7. Unit tests: playlist encode and decode round trips

TC-20, TC-21, TC-23, TC-35: encode and decode round trips for 0 and 1 tracks, unicode and emoji in file name and last known path, and that the playlist name is not stored inside the file. Assert id, reference and order identity.

### 8. Integration tests: atomic save under faults and interruption

TC-22, TC-24 to TC-27, TC-29 (atomic save under faults, interruption, quick successive saves, copy to another folder) plus the self-update cases TC-60 to TC-63 (refreshed reference and Locate result saved with nothing else changed; failed and read-only self-update keep the change in memory with no message) and negatives TC-92, TC-98. Real temporary directory with the fault-injection seam.

### 9. Unit tests: playlist load error classes

TC-30 to TC-33: load error classes (notFound, random bytes and 0-byte file as corrupt, a higher version as unsupportedVersion with that number). Negative: nothing on disk changes on any error.

### 10. Integration tests: load from the real file system including missing audio

TC-22 and TC-34: load from the real file system including a 5000-track playlist and a valid file whose track points to a missing audio file (loads, track present, resolution not attempted). Uses real playlist files written by the store and hand-damaged copies.

### 12. Integration tests: document lifecycle (new, first save, open once, rename, autosave) with stub panels

TC-40 to TC-52: New Playlist creates an untitled document with no file; the Save panel starts in Documents; a stub-chosen folder and name is honoured; cancel and write failure leave it untitled; open one URL once and twice (one document and window), two URLs (two); corrupt, unreadable or newer files create no window; rename keeps tracks and order and failure keeps the old name; autosave writes edits without an explicit save; untitled edits write nothing until first save (provisional). Negatives TC-93, TC-94, TC-96 (no playlist list view, no main window), TC-97. Real document controller, real temporary folder, stubbed panels.

### 13. Integration tests: editor actions, notices and save failure in a playlist window

TC-80 to TC-85 and TC-91: New Playlist window ready for files; drop of 3 files gives 3 rows in dropped order and autosaves; drag reorders and saves; an unsupported drop shows Notice.unsupported, leaves rows unchanged and does not touch the file on disk; a failed save shows Notice.saveFailed while rows keep the edit and disk keeps the old version; Remove drops the row and leaves the audio file untouched. Recording notice stub.

### 14. E2E tests: playlist document workflows in the built app (Save panel, relaunch, rename, open once, kill, self-update)

E2E-1, E2E-2, E2E-6, E2E-7, E2E-8 and TC-28, TC-53, TC-54, TC-72: New Playlist, drop mp3 wav m4a, reorder, save as Dinner via the real Save panel (Documents offered by default), quit, relaunch, open from Finder and Open Recent; rename to Supper; kill the app during a save and relaunch (last good version loads); open the same playlist twice (one window); move an audio file, open and reopen (reference refreshed in the file with no person action); a real .lplaylist opened in Finder opens in the app.

### 15. Declare and export the playlist document type (proposed com.localplayer.playlist, .lplaylist)

Add a CFBundleDocumentTypes entry (role Editor, content type com.localplayer.playlist) and a UTExportedTypeDeclarations entry (identifier, description, extension lplaylist, conforming to a data type) to the bundle Info.plist. Identifier and extension are proposals, not decisions. Do not set the system default handler in code. Coordinate with the open-a-file story: the combined declared set is exactly its three audio types plus this one. Verify with TC-70 and TC-71.

### 16. Integration tests: built bundle declares the playlist type plus exactly the three audio types

TC-70: read the built Info.plist and assert one playlist document type (identifier com.localplayer.playlist, extension lplaylist, role Editor) with an exported type declaration. TC-71: assert the complete set of declared document types is exactly the three audio types plus this one, nothing else (negative: no flac or video types).

### 17. E2E tests: editing in the real window (remove, unsupported drop, read-only save failure, no delete menu)

E2E-3, E2E-4, E2E-5 and TC-95: remove the middle file (audio file still in Finder); drop a .flac (not supported yet message, nothing added); edit while the folder is read-only (could-not-be-saved message, old version after relaunch); scan every menu of the built app and assert no Delete Playlist item exists.

