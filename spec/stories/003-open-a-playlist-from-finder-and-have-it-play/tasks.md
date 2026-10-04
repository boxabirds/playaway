# Tasks

| # | Title | Status | Type | Implements |
|---|-------|--------|------|------------|
| 1 | Implement PlaylistOpenRouter and the open decision on story 4's document read | proposed | implementation | playlist.open.route |
| 3 | Implement PlaylistDocumentController for one window per open playlist and no-disturb focus | proposed | implementation | playlist.document.focus |
| 4 | End the active playlist session when an audio file is opened | proposed | implementation | playlist.playback.replace |
| 5 | Unit tests: open decision table and LoadResult mapping | proposed | test:unit | playlist.open.route |
| 6 | Integration tests: router across document state, shuffle, unreadable and empty playlists | proposed | test:integration | playlist.open.route |
| 7 | Integration tests: re-opening focuses the existing document window and leaves playback alone | proposed | test:integration | playlist.document.focus |
| 8 | Integration tests: opening an audio file replaces playlist playback | proposed | test:integration | playlist.playback.replace |
| 9 | E2E tests: double-click a real playlist in Finder | proposed | test:e2e | playlist.open.route |
| 10 | E2E tests: re-opening a playing playlist and replacing it with an audio file | proposed | test:e2e | playlist.document.focus, playlist.playback.replace |

## Details

### 1. Implement PlaylistOpenRouter and the open decision on story 4's document read

Implement OpenOutcome (init from story 4's LoadResult), OpenAction, PlaylistOpenDecision.decide and PlaylistOpenRouter per the design; PlaylistOpening itself (canOpen, open, endActivePlayback) is defined by story 1. Playlist documents open in their own window through PlaylistDocumentController; the router asks the open document's PlaylistPlayer (story 2) for isPlaying and starts nothing when it is true; start is delegated to story 2's PlaylistPlayer.start() (no start-position logic here); never read or write shuffle/repeat settings; unreadable (notFound, corrupt, unsupportedVersion) and empty playlists start nothing and stop nothing; opening never changes the playlist's name, tracks or order. The router also implements endActivePlayback() (see the replace task). Depends on stories 1, 2 and 4 interfaces. Verify with TC-01 to TC-10, TC-20 to TC-31, TC-41 to TC-43.

### 3. Implement PlaylistDocumentController for one window per open playlist and no-disturb focus

Implement the NSDocumentController subclass: opening a URL that matches an open document returns that document and brings its existing window to the front (no second window); a closed window is treated as not open. Add player(for url:) -> PlaylistPlayer?, returning the PlaylistPlayer owned by the open document for that URL (story 2 holds one per open document) and nil when not open. Already-playing is determined by asking that player's isPlaying, never stored here, and no start is requested when it is playing. No main window, no playlist list, no path-derived identifier (identity is the open document). Other playlists' windows are never closed or moved. Verify with TC-03 to TC-08, TC-32 to TC-34, TC-40.

### 4. End the active playlist session when an audio file is opened

Implement PlaylistOpenRouter.endActivePlayback(): it calls story 2's ActiveSessionRegistry.endActive(), which stops the active PlaylistPlayer, and does nothing when no session is active. Story 1's OpenCoordinator (task 1.5) calls it before engine.play for a supported audio file when a PlaylistOpening is configured; the coordinator change itself is story 1's. Unsupported files leave the playlist playing and show the story 1 notice (endActivePlayback is not called). With no PlaylistOpening supplied the behaviour is exactly story 1's. The name endActivePlayback is a provisional interface shared with stories 1 and 2. Verify with TC-35 to TC-38.

### 5. Unit tests: open decision table and LoadResult mapping

Cover TC-20 to TC-26: PlaylistOpenDecision.decide for every outcome (unreadable, empty, withTracks) crossed with playing and not playing, including that unreadable and empty never stop anything, plus the LoadResult to OpenOutcome mapping for loaded with 5, 1 and 0 tracks, notFound, corrupt and unsupportedVersion. No window, audio or disk.

### 6. Integration tests: router across document state, shuffle, unreadable and empty playlists

Implement the integration rows of the TC-01 to TC-08 matrix (W1 to W4 x shuffle off/on) with the real PlaylistStore reading real playlist files from a temporary directory, story 2's real PlaylistPlayer (seeded random, UserDefaults suite per test) and a recording engine sink; plus TC-27 to TC-31 (one-track, zero-track, corrupt, newer-version, nonexistent file) and the negatives TC-41 (settings unchanged), TC-42 (name, tracks and order unchanged; refreshed references ignored) and TC-43 (nothing playing is stopped). Fixtures come from story 4's store.

### 7. Integration tests: re-opening focuses the existing document window and leaves playback alone

TC-32 (same playlist opened twice, exactly one window, front both times), TC-33 (closed then reopened gives a new window and starts per shuffle), TC-34 (two different playlists, two windows, neither disturbed), and TC-40 (already-playing playlist opened again: no restart, no second window, no start call; track, position, shuffle, repeat unchanged). Uses the real PlaylistDocumentController and real PlaylistPlayer.

### 8. Integration tests: opening an audio file replaces playlist playback

TC-35 (playlist playing, supported file opened: session ended, engine plays from 0:00, state OpenIdle), TC-36 (unsupported file: playlist keeps playing, notice shown), TC-37 (no output device: engine result as story 1 defines), TC-38 (OpenCoordinator built without the playlist-opening dependency behaves exactly as story 1). Real PlaylistPlayer, recording sink.

### 9. E2E tests: double-click a real playlist in Finder

E2E-1 and TC-09 against the built app: open -a LocalPlayer with a real playlist file written by story 4's store (proposed .lplaylist format), shuffle off, from a cold start; assert the playlist opens in its own window, the first track plays, and (TC-44, TC-45) no confirmation dialog, no main window and no playlist list appear. Depends on story 4's store and document type declaration being implemented.

### 10. E2E tests: re-opening a playing playlist and replacing it with an audio file

E2E-2 and TC-10: double-click the same playlist again while it plays and assert the window comes forward and audio is uninterrupted with shuffle on. E2E-3: open a .mp3 while the playlist plays and assert the playlist stops and the file plays. Uses the built app and story 4's real playlist file.

