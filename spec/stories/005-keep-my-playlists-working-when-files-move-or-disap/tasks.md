# Tasks

| # | Title | Status | Type | Implements |
|---|-------|--------|------|------------|
| 1 | Implement TrackReference, TrackStatus and TrackResolver that follow moved files | proposed | implementation | playlist.track.reference |
| 2 | Implement greyed-out missing tracks and the PlaybackGate | proposed | implementation | playlist.track.status |
| 3 | Implement Locate for a missing track with MissingTrackRelinker | proposed | implementation | playlist.missing.locate |
| 4 | Implement FolderMatcher for same-folder reconnection by file name | proposed | implementation | playlist.missing.folder_search |
| 5 | Unit tests: track reference resolution edge cases | proposed | test:unit | playlist.track.reference |
| 6 | Integration tests: moved files are followed on a real file system | proposed | test:integration | playlist.track.reference |
| 7 | Unit tests: track status look and PlaybackGate decisions | proposed | test:unit | playlist.track.status |
| 8 | Integration tests: missing status and refused play on a real file system | proposed | test:integration | playlist.track.status |
| 9 | E2E tests: greyed missing tracks in the real app | proposed | test:e2e | playlist.track.status |
| 10 | Integration tests: Locate across picked file and folder content | proposed | test:integration | playlist.missing.locate |
| 11 | E2E tests: Locate flow through the real menu and file chooser | proposed | test:e2e | playlist.missing.locate |
| 12 | Unit tests: FolderMatcher name matching rules | proposed | test:unit | playlist.missing.folder_search |
| 13 | Integration tests: folder search never changes files and ignores sub-folders | proposed | test:integration | playlist.missing.folder_search |
| 14 | Implement skip-and-mark of missing tracks during automatic play-through | proposed | implementation | playlist.track.autoskip |
| 15 | Unit tests: autoskip decisions, hazard marking and bounded search for the next playable track | proposed | test:unit | playlist.track.autoskip |
| 16 | Integration tests: auto-advance and double-click across missing positions and repeat modes, with hazard marks | proposed | test:integration | playlist.track.autoskip |
| 17 | E2E tests: playlist plays on past a greyed track, which shows a hazard icon and no dialog | proposed | test:e2e | playlist.track.autoskip |

## Details

### 1. Implement TrackReference, TrackStatus and TrackResolver that follow moved files

Implement TrackReference{bookmark,lastKnownPath,fileName}, the single TrackStatus{resolved(URL),missing}, TrackResolving, and the PlaylistDocumentEditing protocol (playlist property and apply(_:toTrack:), which story 4's PlaylistDocument conforms to) per design capability playlist.track.reference. Resolution runs off the main thread: for documents restored at launch it starts on story 6's FirstWindowObserver.firstWindowPresented() (register the resolver as an observer), for a playlist opened later when the document opens. A moved file yields resolved(newURL) plus a refreshed reference that is applied to the open document track by track through apply(_:toTrack:) (skipping any id no longer in playlist.tracks), so the document becomes edited and its autosave writes it once. No save call of your own: the playlist-management story's document save is the only writer. Corrupt bookmark falls back to lastKnownPath, then missing; never throw. Verify with TC-01, TC-03, TC-04, TC-09 and TC-30 to TC-35.

### 2. Implement greyed-out missing tracks and the PlaybackGate

Implement the greyed look for missing tracks in PlaylistTrackRow (system disabled-content colour, inside the playlist document window) and PlaybackGate (decide(for: TrackStatus) -> PlayDecision). A double-click on a row calls PlaylistPlayer.play(track:) (story 2); on refuse the player sets the hazard mark (story 2's ReadabilityMark) and shows no dialog, and the row draws the hazard icon from the published mark. Nothing is written to the document. Covers prd.missing.grey, prd.missing.unplayable and prd.missing.playmarked. Verify with TC-02, TC-05 to TC-08, TC-10, TC-36, TC-37, TC-61 to TC-63, TC-70 to TC-73, E2E-2.

### 3. Implement Locate for a missing track with MissingTrackRelinker

Implement Locate on a missing track's row with MissingTrackRelinker: pick a file, check the located track id against the open document, apply the located track's rebuilt reference and each folder-search match through PlaylistDocumentEditing.apply(_:toTrack:), then clear the hazard mark of every relinked track through story 2's ReadabilityMarkStoring. Results relinked, cancelled, notReadable, editRefused; no marks cleared on any non-success result. No save call of its own. Covers prd.missing.locate. Verify with TC-11 to TC-17, TC-42 to TC-45, TC-64, TC-66, TC-72, E2E-3.

### 4. Implement FolderMatcher for same-folder reconnection by file name

Implement FolderMatching.match(missing:in:) per capability playlist.missing.folder_search: direct children of the located file's folder only, case-insensitive file name equality, only currently missing tracks are candidates, directory listing only (cannot modify files). Duplicate names are deliberately unspecified. The matcher never touches the document; playlist.missing.locate applies its result. Verify with TC-46 to TC-50, TC-60, TC-65, TC-68.

### 5. Unit tests: track reference resolution edge cases

Unit tests for TrackResolver edge cases: TC-30 (zero tracks, document not marked edited), TC-31 (one track), TC-34 (bookmark corrupt and path gone returns missing, no crash). Positive and negative: a resolved track needs no edit; assert before and after state of the stand-in document.

### 6. Integration tests: moved files are followed on a real file system

Integration tests on a real file system with real bookmarks and a real mounted disk image: TC-01, TC-03 (moved file resolves and the document is marked edited with the refreshed reference; autosave rows are blocked until the playlist-management document exists, declare that), TC-04, TC-05, TC-07, TC-09, TC-32 (50 tracks, 25 moved, applied track by track and written by one autosave), TC-33 (corrupt bookmark, path exists), TC-35 (the track id is no longer in the document, so the refresh is skipped and the track still shows resolved this session).

### 7. Unit tests: track status look and PlaybackGate decisions

Unit tests: the row look for resolved and missing (TC-36: status goes from missing to resolved, look changes from grey to normal), PlaybackGate decisions for resolved and missing (TC-37: refuse for missing, engine never called), and that the gate itself never writes the document or sets a mark (marking is done by PlaylistPlayer). Boundaries: zero, one and many tracks.

### 8. Integration tests: missing status and refused play on a real file system

Integration tests on a real file system: Table A rows with action A2 (TC-02, TC-04, TC-06, TC-10): a missing track is refused by the gate, the engine is never called, the hazard mark is set through ReadabilityMarkStoring and no dialog is raised; a resolved track plays. TC-05 and TC-07 assert that merely opening the document sets no hazard mark and does not mark the document edited. TC-74: setting the mark does not change status or write the playlist file.

### 9. E2E tests: greyed missing tracks in the real app

E2E in the built app: TC-08 and E2E-2 (delete a file, open the playlist, double-click that track: it is greyed, nothing plays, a hazard icon appears, no dialog). TC-62: opening a playlist with missing tracks shows greyed rows, no dialog and no hazard icon until a play is attempted or play-through reaches the track. TC-63: no Locate item on a present track.

### 10. Integration tests: Locate across picked file and folder content

Integration tests for Locate across Table B (picked file x folder content): TC-11 to TC-16, TC-43, TC-44, TC-64, TC-66, plus TC-72: relinking a track that carries a hazard mark clears the mark and the row becomes normal; non-success results (cancelled, notReadable, editRefused) leave marks unchanged. Real bookmarks, temporary folders and the real document edit path.

### 11. E2E tests: Locate flow through the real menu and file chooser

E2E tests of the Locate flow in the real app through the real menu and file chooser: TC-17 (P1 and D1 full flow), TC-45 (relink, autosave, quit, reopen: repairs kept without Locate), E2E-3 (Locate, check others from the same folder, quit and reopen), E2E-4 (unmount the disk image, open, mount, reopen).

### 12. Unit tests: FolderMatcher name matching rules

Unit tests of FolderMatcher name matching: TC-46 (case-insensitive), TC-47 (empty folder), TC-49 (only the located track is missing, nothing else changes). Boundary: zero missing tracks and one missing track.

### 13. Integration tests: folder search never changes files and ignores sub-folders

Integration tests that folder search never changes files and ignores sub-folders: TC-48 (sub-folder with a matching name is not matched), TC-50 (50 missing tracks, 50 files present, one document edit), TC-60 (checksums, sizes, names and modification times identical before and after), TC-65 (name not in folder leaves the track grey), TC-68.

### 14. Implement skip-and-mark of missing tracks during automatic play-through

Make PlaylistPlayer (story 2) consult PlaybackGating.decide(for:) before every play. On refuse for a missing track, set that track's session-only hazard mark (ReadabilityMark.unreadable through story 2's ReadabilityMarkStoring) and, for automatic advance, skip it and ask AdvanceDecider for the following track. No dialog or notification. Keep a count of consecutive refusals in the pass and stop when it reaches the track count so an all-missing playlist on repeat cannot spin. The track keeps status missing and nothing is written to the document. Marking call is owned by story 2's playlist.playback.skip_missing; this task supplies the refusal wiring in PlaybackGate.swift and the PlaylistPlayer call site. Covers prd.missing.autoskip. Verify with TC-18 to TC-26 and TC-38 to TC-41.

### 15. Unit tests: autoskip decisions, hazard marking and bounded search for the next playable track

Cover TC-38 (gate decides play(url) for resolved and refuse for missing), TC-39 (empty list: no track, session stops), TC-40 (one-track list that is missing: no track, track marked, session stops), TC-41 (skipped missing track: status stays missing, hazard mark set exactly once per skip through a recording ReadabilityMarkStoring stub). Boundaries: 0, 1 and many tracks; all tracks missing stops after one full pass.

### 16. Integration tests: auto-advance and double-click across missing positions and repeat modes, with hazard marks

Using the real PlaylistPlayer, a real in-memory ReadabilityMarkStoring and a recording engine sink, run the Table C matrix TC-18 to TC-25 (missing position x repeat) and assert both the sink order and that each skipped missing track carries the hazard mark and no dialog is raised. Add TC-70 (double-click on a missing row: gate refuses, engine never called, mark set, no dialog), TC-71 (double-click on a resolved row plays, no mark), TC-73 (double-click twice: one mark, no dialog) and TC-74 (marking never changes status, never edits the document, writes nothing to the playlist file).

### 17. E2E tests: playlist plays on past a greyed track, which shows a hazard icon and no dialog

E2E-5: let a playlist play with a missing track in the middle in the built app; the track is skipped, shows a hazard icon, no dialog or notification appears and the next track plays (TC-26, TC-67). E2E-6: double-click a greyed track; nothing plays, a hazard icon appears, no dialog; quit and reopen the document and confirm the track is greyed without the icon because the mark is session-only.

