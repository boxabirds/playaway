# Tasks

| # | Title | Status | Type | Implements |
|---|-------|--------|------|------------|
| 1 | Add pause and resume to PlaybackEngine | proposed | implementation | playback.transport.pause_resume |
| 2 | Make stop reset position and work from Paused | proposed | implementation | playback.transport.stop |
| 3 | Add seek, position and duration to PlaybackEngine | proposed | implementation | playback.transport.seek |
| 4 | Add next and previous to PlaylistPlayer | proposed | implementation | playback.transport.skip |
| 5 | Add volume level with clamping to PlaybackEngine | proposed | implementation | playback.volume.level |
| 6 | Add mute to PlaybackEngine | proposed | implementation | playback.volume.mute |
| 7 | Build TransportControlsView and TransportViewModel | proposed | implementation | ui.controls.transport |
| 8 | Unit tests: pause and resume state machine | proposed | test:unit | playback.transport.pause_resume |
| 9 | Integration tests: real engine pause and resume with a recording sink | proposed | test:integration | playback.transport.pause_resume |
| 10 | Unit tests: stop from Playing, Paused and Idle | proposed | test:unit | playback.transport.stop |
| 11 | Integration tests: stop then play a new file starts at 0:00 | proposed | test:integration | playback.transport.stop |
| 12 | Unit tests: seek range and boundaries | proposed | test:unit | playback.transport.seek |
| 13 | Integration tests: seek while paused with the real engine | proposed | test:integration | playback.transport.seek |
| 14 | Unit tests: next and previous decisions | proposed | test:unit | playback.transport.skip |
| 15 | Integration tests: skip with the real engine and unreadable next track | proposed | test:integration | playback.transport.skip |
| 16 | Unit tests: volume range and clamping | proposed | test:unit | playback.volume.level |
| 17 | Integration tests: volume applies immediately and leaves system volume alone | proposed | test:integration | playback.volume.level |
| 18 | Unit tests: mute keeps the volume value | proposed | test:unit | playback.volume.mute |
| 19 | Integration tests: mute persists across tracks in a session | proposed | test:integration | playback.volume.mute |
| 20 | Integration tests: controls mirror the live state | proposed | test:integration | ui.controls.transport |
| 21 | E2E tests: transport, skip, volume and mute in the real app | proposed | test:e2e | ui.controls.transport |
| 22 | Implement VolumeSettingsStore: save and restore volume and mute before the first window | proposed | implementation | playback.volume.persist |
| 23 | Unit tests: volume settings store save, restore and fallbacks | proposed | test:unit | playback.volume.persist |
| 24 | Integration tests: volume and mute persistence across launch states with a real defaults suite | proposed | test:integration | playback.volume.persist |
| 25 | E2E tests: volume and mute survive quit and relaunch in the real app | proposed | test:e2e | playback.volume.persist |

## Details

### 1. Add pause and resume to PlaybackEngine

Extend the story 1 PlaybackEngine with isPaused, position, pause() and resume(). pause() while Playing silences immediately and keeps position; resume() while Paused continues from that position. Both are no-ops in any other state. Do not change story 1 members. Verify with TC-01 to TC-03, TC-05, TC-06, TC-09, TC-10.

### 2. Make stop reset position and work from Paused

Extend the existing stop() so that from Playing or Paused it ends playback, sets state Idle and position 0:00, and is a no-op from Idle. Volume and mute are untouched. Verify with TC-03, TC-07, TC-11, TC-14.

### 3. Add seek, position and duration to PlaybackEngine

Add duration and seek(toSeconds:) -> Bool. Valid range is 0 to duration inclusive; below 0, above duration, NaN or no track loaded returns false with position and state unchanged. Playing stays Playing and Paused stays Paused. Step size is an open question; do not constrain it. Verify with TC-40 to TC-46.

### 4. Add next and previous to PlaylistPlayer

Add next() and previous() to PlaylistPlayer in Sources/LocalPlayer/Playlists/PlaylistPlayer+Skip.swift, calling story 2's decider with skipForward and skipBackward. Rules: Next with repeat one moves to the following track (decided). Previous steps back through the current order (listed order, or the shuffle pass being played when shuffle is on, never rebuilding the pass). On the first track of that order Previous plays the last track of the order when repeat is on (all or one) and does nothing (.stay) when repeat is off; this is an interpretation of the owner's words pending confirmation, label it as such in code comments. Next on the last track: repeat off ends playback, repeat all wraps (provisional). No playlist session means both calls are ignored. Verify with TC-20 to TC-38, TC-90 to TC-97, TC-85, TC-87. Story 2 owns the decider events; do not edit its capability from here.

### 5. Add volume level with clamping to PlaybackEngine

Add volume to PlaybackEngine and AVPlaybackEngine in Sources/LocalPlayer/Playback/ with named constants volumeMinimum 0.0, volumeMaximum 1.0, volumeDefault 1.0 (VolumeLimits.swift). Values in range apply immediately without interrupting playback; out-of-range values clamp; non-numbers are refused. The level is the player's own output gain only: never read or write the Mac system volume (decided requirement prd.ctrl.volume_scope). Every applied (clamped) level is passed to the settings store from the persistence task. Verify with TC-50 to TC-56 and TC-84.

### 6. Add mute to PlaybackEngine

Add isMuted and setMuted(_:) to PlaybackEngine and AVPlaybackEngine. Muting silences output without changing the volume value; unmuting restores audio at that value; mute is allowed while Idle and applies to every track in the session. Changing the volume while muted stays silent (provisional). Every mute change is passed to the settings store from the persistence task, under its own key, separate from the volume. Verify with TC-60 to TC-64, TC-83.

### 7. Build TransportControlsView and TransportViewModel

Build the self-contained controls view (Play/Pause, Stop, Previous, Next, position control with elapsed time, volume control, Mute) from standard system controls, bound to a view model that mirrors engine and session state, including changes made from outside the view. Set the accessibility identifiers playback.playpause, playback.stop, playback.previous, playback.next, playback.position, playback.volume and playback.mute (the last two are the ids the on-screen-simplicity manifest already records, the rest are proposed). Track-dependent controls are unavailable when nothing is loaded (provisional). Expose every action as a view-model method with ids play, pause, stop, seek, next, previous, volume, mute for the AppleScript story. The host window is open; do not choose one. Verify with TC-70 to TC-74, TC-86.

### 8. Unit tests: pause and resume state machine

Cover the Idle, Playing and Paused rows for Pause and Play in TC-01 to TC-03, TC-05, TC-06, TC-09, TC-10 against a fake audio backend, asserting state and position before and after. Negatives TC-80 (pause never moves position) and TC-81 (resume never restarts from 0:00).

### 9. Integration tests: real engine pause and resume with a recording sink

TC-13: with the real AVFoundation engine and a recording sink, play a real 30 second fixture, pause, wait, resume; assert the sink shows silence then audio resuming from the paused frame, not from the start. Use the real mp3, wav and m4a fixtures.

### 10. Unit tests: stop from Playing, Paused and Idle

TC-03, TC-07, TC-11: stop from Idle is a no-op, from Playing and Paused ends playback with state Idle and position 0. Assert state, position, volume and mute before and after; volume and mute must be unchanged.

### 11. Integration tests: stop then play a new file starts at 0:00

TC-14 with the real engine and recording sink: play, stop, then play a new real fixture; assert the sink shows the new file starting at 0:00 and the previous file silent.

### 12. Unit tests: seek range and boundaries

TC-04, TC-08, TC-12 and boundaries TC-40 to TC-45: seek 0, exactly duration, duration plus 0.001, -1, NaN and no track loaded. Assert the Bool result and that position and transport state are unchanged on every false result (TC-82). Playing stays Playing, Paused stays Paused on success.

### 13. Integration tests: seek while paused with the real engine

TC-46 with the real engine and recording sink: pause a real fixture, seek to 10 seconds, assert it stays Paused, position is 10, no audio reaches the sink, then resume and assert audio continues from 10 seconds.

### 14. Unit tests: next and previous decisions

Unit tests for the skip decisions: the context x direction x repeat x shuffle matrix TC-20 to TC-38 and TC-90 to TC-96 with a 5-track in-memory playlist and a seeded shuffle pass. Positive and boundary: TC-25 Next with repeat one moves to the following track (decided); TC-28, TC-90, TC-93, TC-94, TC-96 Previous on the first track of the order with repeat on goes to the last track (interpretation pending owner confirmation, keep these rows grouped so they can be changed together); TC-27, TC-36, TC-92 Previous on the first track with repeat off does nothing. Negative: TC-85 single file ignored, TC-87 Next at the end of a repeat-off playlist does not restart it.

### 15. Integration tests: skip with the real engine and unreadable next track

Integration tests for skip with the real engine and a recording sink: TC-37 Next from track 3 stops track 3 and starts track 4 at 0:00; TC-38 an unreadable next track is marked and the following track plays with no dialog (story 2 rule); TC-97 Previous on the first track with repeat all stops track 1 and starts the last track at 0:00 (interpretation pending owner confirmation). Use real encoded fixtures and a real unreadable mp3.

### 16. Unit tests: volume range and clamping

TC-50, TC-51, TC-53, TC-54, TC-55: volume 0.0, 1.0, -0.1 (clamped to 0.0), 1.1 (clamped to 1.0) and NaN (refused, unchanged). Use the named constants, not literals, in assertions. Assert level before and after.

### 17. Integration tests: volume applies immediately and leaves system volume alone

Integration tests: TC-52 volume 0.5 sets sink gain 0.5 immediately; TC-56 a volume change during playback does not interrupt the track; TC-84 (decided requirement prd.ctrl.volume_scope) the Mac system volume is not changed by volume or mute and is not read to set the level, asserted by reading the system output volume before and after. Real engine, recording sink.

### 18. Unit tests: mute keeps the volume value

TC-60 to TC-63: mute on at volume 0.7 (silent, value still 0.7), mute off (gain 0.7), volume 0.3 while muted (value 0.3, still silent, provisional), mute while Idle (allowed). Negative TC-83: muting never changes the volume value.

### 19. Integration tests: mute persists across tracks in a session

Integration tests: TC-64 mute persists across tracks in a session (a new file started while muted is silent), with the real engine and recording sink. Also TC-121 mute and volume are stored independently: mute on, then volume set to 0.3, engine reconstructed gives mute on and volume 0.3.

### 20. Integration tests: controls mirror the live state

Integration tests for TransportControlsView and TransportViewModel: TC-70 playing shows Pause and elapsed time advances; TC-71 paused shows Play with time frozen; TC-72 idle disables track-dependent controls while volume and Mute stay available (provisional); TC-73 volume 0.5 with Mute on is shown; TC-74 a pause from outside the view (script) switches the control to Play; TC-75 launching with saved volume 0.4 and mute on, the first published state already shows 0.4 and Mute on, never the default.

### 21. E2E tests: transport, skip, volume and mute in the real app

E2E tests of the real app via UI automation: E2E-1 pause and resume (resumes within a second of the paused time), E2E-2 seek while playing and while paused, E2E-3 Next then Previous in a 3-track playlist, E2E-4 volume to the left end, half, Mute, Mute, E2E-5 Next and Previous on a single mp3 change nothing, and TC-86 no confirmation dialog for any control. Quit-and-relaunch persistence is covered by the separate persistence e2e task (E2E-6).

### 22. Implement VolumeSettingsStore: save and restore volume and mute before the first window

Implement VolumeSettingsStoring (load, saveVolume, saveMuted) over an injected UserDefaults with two separate keys, volumeSettingKey (Double) and muteSettingKey (Bool), named constants. load() runs before any window is created: a missing, out-of-range, NaN or wrong-type volume falls back to volumeDefault (1.0); a missing or non-boolean mute falls back to muteDefault (false); each falls back independently. No message or dialog for damaged values; write failures are ignored. The engine is constructed with the loaded values and calls the save methods from its setters, saving clamped values. Only these two keys are touched. Verify with TC-100 to TC-123, TC-75, TC-88, TC-89.

### 23. Unit tests: volume settings store save, restore and fallbacks

Unit tests against an in-memory defaults fake: TC-116 stored 0.0 and TC-117 stored 1.0 restore as stored (valid boundaries); TC-118 NaN and TC-119 -0.001 fall back to volumeDefault; TC-122 the engine's initial volume and mute are applied at construction, before any view exists; TC-123 a volume set to 2.0 is saved as the clamped 1.0, never 2.0. Negative: a damaged volume must not discard a valid stored mute and vice versa.

### 24. Integration tests: volume and mute persistence across launch states with a real defaults suite

Implement the 16-row launch-state matrix TC-100 to TC-115 (stored volume none, valid 0.4, out of range 1.5, wrong type text, crossed with stored mute none, true, false, wrong type) against a unique real UserDefaults suite per test, asserting volume and mute on the engine before any window exists. Plus TC-120 volume set to 0.6 then a reconstructed engine starts at 0.6, TC-88 a damaged value gives no crash, no message and no dialog, TC-89 only the volume and mute keys are written, and TC-75 with the controls view. Fixtures: values written by the real store plus hand-damaged ones.

### 25. E2E tests: volume and mute survive quit and relaunch in the real app

E2E-6 against the built app: set the volume to about a quarter, press Mute, quit, relaunch; assert the volume control shows about a quarter and Mute shows on from the first frame, and that unmuting restores sound at about a quarter. Repeat after deleting the app's saved settings: the volume control shows full and Mute is off. Assert no dialog appears on either launch.

