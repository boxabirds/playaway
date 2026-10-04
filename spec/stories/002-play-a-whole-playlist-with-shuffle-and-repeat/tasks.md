# Tasks

| # | Title | Status | Type | Implements |
|---|-------|--------|------|------------|
| 1 | Implement AdvanceDecider for order, advance, repeat and skip events | proposed | implementation | playlist.playback.advance |
| 2 | Implement ShuffleOrder with injected random generator | proposed | implementation | playlist.playback.shuffle_order |
| 3 | Implement PlaylistPlayer track loop with ReadabilityMark for unreadable and missing tracks | proposed | implementation | playlist.playback.skip_unreadable |
| 4 | Implement PlayModeSettings and the Shuffle and Repeat controls | proposed | implementation | playlist.controls.modes |
| 5 | Implement persistence of Shuffle and Repeat across launches | proposed | implementation | playlist.settings.persist |
| 6 | Unit tests: AdvanceDecider events matrix, skip events and boundaries | proposed | test:unit | playlist.playback.advance |
| 7 | Integration tests: full playlist runs through the real engine sink | proposed | test:integration | playlist.playback.advance |
| 8 | Unit tests: ShuffleOrder permutation properties | proposed | test:unit | playlist.playback.shuffle_order |
| 9 | Integration tests: shuffled pass plays each track once and leaves stored order alone | proposed | test:integration | playlist.playback.shuffle_order |
| 10 | Unit tests: unreadable classification marks a track like an engine failure | proposed | test:unit | playlist.playback.skip_unreadable |
| 11 | Integration tests: unreadable tracks skipped at every position | proposed | test:integration | playlist.playback.skip_unreadable |
| 12 | E2E tests: hazard icon on an unreadable track in the real app | proposed | test:e2e | playlist.playback.skip_unreadable |
| 13 | Unit tests: Shuffle and Repeat control state logic | proposed | test:unit | playlist.controls.modes |
| 14 | Integration tests: pressing a control never interrupts the playing track | proposed | test:integration | playlist.controls.modes |
| 15 | E2E tests: Shuffle and Repeat controls in the real window | proposed | test:e2e | playlist.controls.modes |
| 16 | Unit tests: failed save keeps the new setting for this launch | proposed | test:unit | playlist.settings.persist |
| 17 | Integration tests: stored settings restored on launch with real defaults | proposed | test:integration | playlist.settings.persist |
| 18 | E2E tests: settings survive quit and relaunch | proposed | test:e2e | playlist.settings.persist |
| 19 | Implement PlaylistPlayer.start and ActiveSessionRegistry for one active session | proposed | implementation | playlist.playback.start |
| 20 | Implement missing-track skip and hazard mark through TrackResolving and PlaybackGate | proposed | implementation | playlist.playback.skip_missing |
| 21 | Unit tests: start position and one-active-session registry | proposed | test:unit | playlist.playback.start |
| 22 | Integration tests: starting a playlist ends other playback | proposed | test:integration | playlist.playback.start |
| 23 | E2E tests: two playlist windows, only one plays | proposed | test:e2e | playlist.playback.start |
| 24 | Unit tests: missing-track skip and mark loop with stubbed resolver and gate | proposed | test:unit | playlist.playback.skip_missing |
| 25 | Integration tests: missing tracks skipped and marked with real gate and fixtures | proposed | test:integration | playlist.playback.skip_missing |
| 26 | E2E tests: missing track skipped and marked with the hazard icon in the real app | proposed | test:e2e | playlist.playback.skip_missing |
| 27 | Implement PlaylistPlayer.play(track:) for a double-clicked row | proposed | implementation | playlist.playback.play_track |
| 28 | Unit tests: play-track pass rebuild and one-track boundary | proposed | test:unit | playlist.playback.play_track |
| 29 | Integration tests: play-track across shuffle, other playback and track state | proposed | test:integration | playlist.playback.play_track |
| 30 | E2E tests: double-clicking a track row in the real app | proposed | test:e2e | playlist.playback.play_track |

## Details

### 1. Implement AdvanceDecider for order, advance, repeat and skip events

Implement AdvanceDeciding per the design: events start, trackFinished, skipForward, skipBackward and answers play(track), stop or stay. Owner decisions: skipForward always moves to the following track (repeat one does not replay); skipBackward at the first track goes to the last track of the order when repeat is on and returns stay when repeat is off. Interpretation pending owner confirmation, implement but keep the rule in one place: repeat on means all or one; with shuffle on both events step through the current pass; skipForward at the last track wraps like repeat all with repeat one. Empty playlist: stop for start, trackFinished and skipForward, stay for skipBackward. Never throws, pure. Verify with TC-01 to TC-22, TC-74, TC-76 to TC-78, TC-140 to TC-181.

### 2. Implement ShuffleOrder with injected random generator

Implement ShuffleOrdering.pass(for:startingWith:) with an injected random generator: a random permutation of Track ids with each track once and the requested first track, if any, first. The same call serves a playlist start (no required first track), a double-click on a track and turning shuffle on mid-song (owner decisions). Turning shuffle off continues in listed order from the current track. Never mutates or writes the Playlist. Verify with TC-04 to TC-06, TC-10 to TC-12, TC-22, TC-39, TC-40, TC-88, TC-98, TC-119, TC-122, TC-125, TC-135.

### 3. Implement PlaylistPlayer track loop with ReadabilityMark for unreadable and missing tracks

Implement the PlaylistPlayer track loop: resolve each chosen track through TrackResolving, refuse missing tracks through PlaybackGating, classify the resolved file, play it, and on unreadable (classifier fileNotReadable or engine failed) record ReadabilityMark.unreadable in ReadabilityMarkStoring (session only, keyed by Track.id) and ask the decider again; noOutputDevice marks nothing and stops the session. The mark means could not be played this session and is used for both unreadable and missing tracks (missing handled in the skip_missing task). ReadabilityMarkStoring has mark(of:), markUnreadable(_:) and clearMark(of:); clearMark(of:) is called by story 5's Locate when a missing track becomes playable, and clearing an unmarked track changes nothing. Iterative loop, no recursion, no dialog. Story 5's PlaylistTrackRow draws the hazard icon. Verify with TC-60 to TC-67, TC-71, TC-75, TC-96 plus a clearMark unit test.

### 4. Implement PlayModeSettings and the Shuffle and Repeat controls

Implement PlayModeSettings with two independent published values (shuffleOn, repeatMode), toggleShuffle and cycleRepeat (off, all, one, off), and two separate controls that show the current state in every playlist window. The settings object is shared by all open playlist windows (provisional), so a press in one window is reflected in the others. Changes apply to the next decision only and never interrupt the playing track. Do not decide placement or glass styling here. Verify with TC-30 to TC-40, TC-72, TC-73 and TC-104.

### 5. Implement persistence of Shuffle and Repeat across launches

Implement PlayModeStoring over UserDefaults with keys shuffleEnabled (Bool) and repeatMode (String off, all, one). Save on every change; load before any window shows; missing or invalid values fall back to off individually; a failed save keeps the value in memory for the launch. Suite injected for tests. Verify with TC-50 to TC-59.

### 6. Unit tests: AdvanceDecider events matrix, skip events and boundaries

Cover TC-01 to TC-18, TC-74, TC-76 to TC-78 (repeat x shuffle x event) and the skip matrix TC-140 to TC-181: skipForward and skipBackward across first, middle and last position x repeat off, all, one x shuffle off, on with a seeded pass, including repeat one next moving on, previous at the first track going to the last track when repeat is on and staying when off, one-track and empty playlists. Mark the interpretation rows (TC-156, TC-157, and the shuffle-pass stepping rows) as pending owner confirmation in test names. Assert Next values exactly, including stay never reaching the engine.

### 7. Integration tests: full playlist runs through the real engine sink

Implement TC-19 (repeat off, full 5-track run then Stopped), TC-20 (repeat all wraps to track 1), TC-21 (repeat one plays track 1 three times in a row) using real PlaylistPlayer, real decider, a stubbed TrackResolving that resolves every track, and real encoded 3 to 5 second fixtures with a recording sink asserting the order of plays. Tracks are Track values (id UUID, TrackReference with real bookmark data) built in memory; no playlist file is read or written.

### 8. Unit tests: ShuffleOrder permutation properties

Property tests for ShuffleOrdering with a seeded generator: permutation of all track ids, each exactly once; requested first track is first; empty playlist returns an empty pass; a one-track playlist returns that track; the Playlist value is unchanged afterwards. Cover the rebuild used by a double-click and by shuffle on mid-song (TC-39, TC-119, TC-122, TC-125, TC-135).

### 9. Integration tests: shuffled pass plays each track once and leaves stored order alone

TC-22 (shuffle on, repeat off: sink shows every track exactly once in the seeded order then Stopped), TC-70 (stored playlist order is identical before and after the pass), TC-39 (shuffle turned on mid-playback of track 3 keeps track 3 playing, rest follows the seeded permutation), TC-40 (shuffle turned off mid-playback of track 3, track 4 plays next).

### 10. Unit tests: unreadable classification marks a track like an engine failure

TC-65: a classifier result of fileNotReadable marks the track exactly as an engine failed result does. Assert ReadabilityMarkStore state before (readable) and after (unreadable), that other tracks remain readable, and that a good track is never marked. Marks are keyed by Track.id.

### 11. Integration tests: unreadable tracks skipped at every position

TC-60 to TC-64 (middle, last, first at start, only track, two in a row, all with repeat off) using the real header-zeroed mp3 fixture and a stubbed TrackResolving that resolves every track; TC-66 and TC-75 (noOutputDevice marks nothing and stops, no advance). Assert marks in the ReadabilityMarkStore and the order of sink plays.

### 12. E2E tests: hazard icon on an unreadable track in the real app

TC-67, TC-71 and E2E-2 in the built app: a playlist with a real zero-header mp3 in the middle; start it; the hazard icon appears on that row only, no dialog or notification appears, and the next track plays. Missing-file e2e coverage is in the skip_missing tasks.

### 13. Unit tests: Shuffle and Repeat control state logic

TC-30 to TC-37 (repeat off to all to one to off, three presses return to off, shuffle toggle both ways) plus TC-72 and TC-73 (changing one control never modifies the other value). Assert the published state after every press.

### 14. Integration tests: pressing a control never interrupts the playing track

TC-38: with a track playing through the recording sink, press Shuffle and Repeat and assert the sink shows no stop or restart and the position is unchanged; the new value affects only the next decision. TC-104: with two playlist windows open, press Shuffle in the first and assert the second window's control shows the same state (settings shared, provisional).

### 15. E2E tests: Shuffle and Repeat controls in the real window

E2E-1 (3-track playlist, repeat off, shuffle off runs in order then stops) and E2E-4 (pressing Repeat three times shows all, one, off in that order; Shuffle shows on then off) in the built app, driven by UI automation.

### 16. Unit tests: failed save keeps the new setting for this launch

TC-59: with a store whose save throws or fails, pressing a control still updates the in-memory state and the control shows it; no message is shown. Assert state before and after.

### 17. Integration tests: stored settings restored on launch with real defaults

TC-50 to TC-58 using a unique real UserDefaults suite per test: all six stored combinations restored, nothing stored gives off and off, an unrecognised repeat string falls back to off while a valid shuffle value is kept, a wrong-typed shuffle falls back to off while a valid repeat is kept.

### 18. E2E tests: settings survive quit and relaunch

E2E-3: in the built app set Shuffle on and Repeat all, quit, relaunch, and assert both controls show on and all. Also verify a clean first launch shows off and off.

### 19. Implement PlaylistPlayer.start and ActiveSessionRegistry for one active session

Implement PlaylistPlayer.start(), isPlaying and ActiveSessionRegistry (begin, endActive) so only one session is active (owner decision, confirmed): start with at least one track registers the session, ends any other active session (it stops advancing; the shared engine's next play replaces the audio), reads PlayModeSettings directly and never writes it, then plays the first listed track (shuffle off) or the first track of a random ShuffleOrdering pass (shuffle on). An empty playlist starts nothing and does not end the active session. end() detaches from engine events and does not stop audio itself. Verify with TC-80 to TC-91 and TC-103.

### 20. Implement missing-track skip and hazard mark through TrackResolving and PlaybackGate

Before any play call PlaylistPlayer asks TrackResolving for the status and PlaybackGating for the decision. When the gate refuses a missing track the engine is not called, ReadabilityMark.unreadable is recorded for the track (hazard icon, in addition to story 5's grey look; owner decision, confirmed, superseding the earlier silent skip) and the loop asks the decider for the next track. Status is re-read every time. All missing with repeat off ends Stopped with every track marked and the engine never called; repeat on with all missing is the accepted tight-loop risk. No dialog, mark is session only and never written to the playlist file. Verify with TC-92 to TC-100, TC-101, TC-105.

### 21. Unit tests: start position and one-active-session registry

Implement the unit rows of the start matrix (shuffle off/on x idle x 0, 1, 5 tracks): TC-80, TC-81, TC-82, TC-86, TC-87, TC-88 with a seeded generator, an in-memory Playlist, a stub engine and a stub resolver; assert exact first track, and that an empty playlist starts nothing. TC-103: with two players sharing one ActiveSessionRegistry, begin(B) ends A exactly once and B is the only active session. Assert state before and after.

### 22. Integration tests: starting a playlist ends other playback

Implement the integration rows of the start matrix with two real PlaylistPlayer values sharing one real ActiveSessionRegistry and a recording sink: TC-83 and TC-89 (empty playlist, other keeps playing untouched, nothing stopped), TC-84 and TC-90 (1 track, other ended, the track plays), TC-85 (shuffle off, 5 tracks, other ended, first listed plays), TC-91 (shuffle on, seeded pass first track plays). Negative: the saved shuffle and repeat values are never written by a start (TC-102), no playlist file is written.

### 23. E2E tests: two playlist windows, only one plays

E2E-5 in the built app: open two real playlist documents in two windows, start the first, then start the second. Assert the first stops, only the second plays, and each window shows the same shared Shuffle and Repeat state. Also confirm that starting an empty playlist leaves the playing one untouched.

### 24. Unit tests: missing-track skip and mark loop with stubbed resolver and gate

With a stubbed TrackResolving and PlaybackGating and an in-memory playlist: a missing track is refused, marked unreadable in the store and skipped, never reaches the engine (TC-99); first, middle and last positions and all-missing with repeat off (TC-92 to TC-95); a missing and an unreadable track together (TC-96); status re-read on a second pass (TC-100). Assert state before and after: marks recorded, session state, engine call count.

### 25. Integration tests: missing tracks skipped and marked with real gate and fixtures

Real PlaybackGate, real classifier, real fixture files, stubbed resolver, recording engine sink: TC-92 to TC-98, TC-100, TC-101 (mark recorded, no dialog, not written to the playlist file), shuffle on with one missing track skipped and marked while the other four play once each (TC-98), repeat all wrap with a missing last track (TC-97).

### 26. E2E tests: missing track skipped and marked with the hazard icon in the real app

TC-105 and E2E-6 in the built app: delete the real file of the middle track in a copy of the fixture folder, open and start the playlist; the middle row shows the hazard icon, no dialog or notification appears, and the next track plays.

### 27. Implement PlaylistPlayer.play(track:) for a double-clicked row

Implement play(track:): resolve, gate, classify, then register with ActiveSessionRegistry (ending any other session), rebuild the shuffle pass starting at the chosen track when shuffle is on (ShuffleOrdering.pass(for:startingWith:)), and play the track from 0:00 as the current track; with shuffle off the playlist continues with the following listed track. A missing or unreadable track is marked (ReadabilityMark.unreadable), nothing is played, the registry is not touched and playback already running is unchanged (interpretation pending owner confirmation). noOutputDevice marks nothing; engine failed after the checks marks the track and leaves this session Stopped. No playlist write, no settings change. Story 5's PlaylistTrackRow forwards the double-click to this method. Verify with TC-110 to TC-135.

### 28. Unit tests: play-track pass rebuild and one-track boundary

With a stubbed resolver, gate, classifier and recording engine: TC-135 (one-track playlist, shuffle on, pass holds one track), TC-134 (chosen last track with repeat off plays then stops), and the idle rows TC-110 to TC-112 and TC-119 to TC-121 asserting current track, engine calls and marks before and after; a track not in this playlist is ignored.

### 29. Integration tests: play-track across shuffle, other playback and track state

Implement the integration rows TC-110 to TC-127 (shuffle x other playback idle, same playlist, other playlist x chosen track playable, missing, unreadable) with two PlaylistPlayer values sharing one registry, the real gate and classifier and a recording sink; plus TC-130 (blocked track does not touch the registry), TC-131 (saved shuffle and repeat unchanged), TC-132 (engine failed after the other session ended), TC-133 (no output device). Real encoded fixtures, seeded generator.

### 30. E2E tests: double-clicking a track row in the real app

TC-128, TC-129, E2E-7 and E2E-8 in the built app: double-click the third row while another track plays (the other stops, track 3 plays from its beginning); double-click a row whose real file was deleted (hazard icon appears, the music carries on); with shuffle on the remaining tracks follow in a random order after the chosen one.

