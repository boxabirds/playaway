# PRD

Pause, resume, stop, seek, next, previous, volume and mute, with controls that always show the live state.

## Problem

Playing a file or a playlist is only half of listening. People also need to stop for a phone call, jump to the part of a song they want, skip a track they do not like, and turn the sound down without leaving the app. Music (formerly iTunes) buries these controls among many others, and other players show them in unfamiliar ways or leave some out. Without standard, predictable controls the person cannot tell whether the player is paused or stopped, how far into the track they are, or whether the sound is muted or just quiet.

## Solution

The player offers the standard controls people expect: pause and resume, stop, seek to any point in the track, next and previous track, a volume control and a mute control. Each control does exactly one clear thing and always shows the current state: whether the track is playing or paused, how far into it the person is, how loud it is, and whether it is muted. Pausing keeps the person's place; stopping puts them back at the start; muting silences the sound without losing the volume they had chosen. This resolves the confusion and missing controls described above, and it does so with nothing more than the controls the person already knows.

## User Experience

## Golden path
1. A file or a playlist is playing, and the person can see the controls for it.
2. They press Pause. The sound stops at once and the control now offers Play. The position stays where it was.
3. They press Play. The sound continues from exactly where it stopped.
4. They drag the position control to the middle of the track. The sound continues from there.
5. They press Next. The following track in the playlist starts. Previous goes back as the playlist order and shuffle setting dictate.
6. They move the volume control down. The sound gets quieter straight away. They press Mute. The sound stops being heard, the volume control still shows the level they chose, and Mute shows it is on. Pressing Mute again brings the sound back at that level.
7. They press Stop. Playback ends and the position returns to the start of the track.
8. They quit the app and open it again. The volume control shows the level they left, and Mute shows the state they left.

## Alternate flows
- **Nothing is playing and nothing is loaded (provisional):** the controls that need a track (Pause, Stop, position, Next, Previous) appear unavailable. The volume and Mute controls remain available so the person can set them before playing.
- **Paused and the person moves the position control:** the track stays paused at the new position until the person presses Play.
- **Playing a single audio file (not a playlist), person presses Next or Previous (provisional):** nothing happens.
- **Next on the last track of a playlist with Repeat off (provisional, matching playlist playback):** playback ends.
- **Next on the last track with Repeat all:** the first track plays.
- **Next with Repeat set to one:** the following track starts. Repeat one only replays a track when it finishes by itself.
- **Previous in the middle of a playlist:** the preceding track starts. With Shuffle on, Previous steps back through the tracks in the order they are being played.
- **Previous on the first track of the order, Repeat on (all or one):** the last track of the order plays. This is an interpretation of the owner's words ("last track if it's on repeat, nothing if not, previous random if random"), pending owner confirmation.
- **Previous on the first track of the order, Repeat off:** nothing happens and the first track keeps playing. Interpretation pending owner confirmation.
- **Volume pushed to either end:** it stops at silent or at full; it never goes beyond.
- **Saved volume cannot be read at launch:** the app starts at its normal default level with Mute off, and does not show any message.

## Empty and error states
- Empty state: with nothing loaded the controls that need a track are unavailable, as above.
- Error state: a request that makes no sense (for example a position beyond the end of the track, only possible from a script) is refused and playback is left as it was. No message is shown for ordinary controls.

## Structure
A transport area with Play/Pause, Stop, Previous and Next; a position control with the elapsed time; a volume control and a Mute control. Which window hosts these controls when a single audio file is playing is not decided yet.

## Behaviour
- Controls always show the real state. If playback is paused by any means, the Play/Pause control shows Play.
- Pressing Pause never moves the position.
- Changing the volume while muted does not unmute (provisional).
- A volume or Mute change takes effect immediately without interrupting the track.
- The volume level and the Mute state are remembered between launches.
- The volume is the player's own level. It is independent of the Mac's system volume.

## Explicit non-behaviours
- Does not restart the track when resuming from pause.
- Does not change the volume when muting.
- Does not change the person's Mac system volume.
- Does not ask for confirmation for any of these controls.
- Does not add crossfade, equaliser, playback speed or other extra controls.

## Pause keeps the place

> Anchor: `prd.ctrl.pause`

WHILE a track is playing WHEN the person presses Pause THE SYSTEM SHALL silence the audio and keep the current position.

## Play continues from the paused position

> Anchor: `prd.ctrl.resume`

WHILE playback is paused WHEN the person presses Play THE SYSTEM SHALL continue playing from the paused position.

## Stop returns to the start

> Anchor: `prd.ctrl.stop`

WHILE a track is playing or paused WHEN the person presses Stop THE SYSTEM SHALL end playback and set the position to the start of the track.

## Seek to a chosen position

> Anchor: `prd.ctrl.seek`

WHEN the person chooses a position between the start and the end of the current track THE SYSTEM SHALL continue from that position, remaining paused if playback was paused.

## Positions outside the track are refused

> Anchor: `prd.ctrl.seek_range`

IF a requested position is before the start or after the end of the current track THEN THE SYSTEM SHALL NOT change the position or the playback state.

## Next track

> Anchor: `prd.ctrl.next`

WHILE a playlist is playing WHEN the person presses Next THE SYSTEM SHALL start the track that the playlist order and the shuffle setting select as the following track, including when Repeat is set to one.

## Previous track

> Anchor: `prd.ctrl.previous`

WHILE a playlist is playing WHEN the person presses Previous THE SYSTEM SHALL start the track that the current order selects as the preceding track, where the current order is the listed order, or the order the tracks are being played in when Shuffle is on; and WHEN the current track is the first of that order, THE SYSTEM SHALL start the last track of that order if Repeat is on (all or one), and SHALL leave playback unchanged if Repeat is off (interpretation of the owner's words, pending owner confirmation).

## Next and Previous do nothing outside a playlist

> Anchor: `prd.ctrl.skip_single`

WHILE a single audio file that is not part of a playlist is playing WHEN the person presses Next or Previous THE SYSTEM SHALL NOT change playback.

## Volume changes immediately and stays in range

> Anchor: `prd.ctrl.volume`

WHEN the person changes the volume THE SYSTEM SHALL apply the new level immediately and SHALL keep the level between silent and full.

## Mute keeps the chosen volume

> Anchor: `prd.ctrl.mute`

WHEN the person presses Mute THE SYSTEM SHALL silence the audio without changing the chosen volume level, and WHEN the person presses Mute again THE SYSTEM SHALL restore the audio at that level.

## Volume is the player's own level

> Anchor: `prd.ctrl.volume_scope`

THE SYSTEM SHALL apply the volume control and the Mute control only to the player's own sound level, and SHALL NOT change the Mac's system volume.

## Volume and Mute are remembered

> Anchor: `prd.ctrl.volume_persist`

WHEN the app is launched THE SYSTEM SHALL restore the volume level and the Mute state that the person last chose, and WHERE no valid saved volume level exists THE SYSTEM SHALL start at the normal default level with Mute off.

## Controls show the live state

> Anchor: `prd.ctrl.state`

THE SYSTEM SHALL show on the controls whether playback is playing or paused, the elapsed position, the volume level and whether Mute is on.

## Acceptance criteria

A non-technical person can verify these by hand with a 3 minute mp3 and a 3-track playlist.
1. Play the mp3, press Pause: the sound stops and the control shows Play. Note the time shown.
2. Wait 10 seconds and press Play: the sound continues from the noted time, not from the start.
3. Drag the position control to about the middle: the sound continues from there. Pause, drag again: it stays paused at the new time.
4. Press Stop: the sound ends and the time shows 0:00.
5. Start the playlist on track 2 and press Next: track 3 plays. Press Previous: track 2 plays.
6. With Repeat set to one, press Next: the following track plays, not the same track again.
7. On track 1 with Repeat off, press Previous: nothing changes. Turn Repeat on (all) and press Previous: the last track plays. (Reading of the owner's answer, pending confirmation.)
8. Play the single mp3 and press Next, then Previous: nothing changes.
9. Drag the volume control to the far left and then the far right: it stops at the ends and the sound is silent at the left end.
10. Set the volume to about half, press Mute: no sound, and the volume control still shows about half. Press Mute again: sound returns at about half.
11. Change the Mac's system volume while the player is at about half: the player's volume control does not move, and moving the player's volume control does not move the Mac's system volume.
12. Set the volume to about a quarter, press Mute, quit the app and open it again: the volume control shows about a quarter and Mute shows on. Unmute: sound returns at about a quarter.
13. In every step above, the controls show the real state: Play or Pause, the elapsed time, the volume and the mute state.

## Open questions

These are not decided and must not be assumed by anyone implementing this story. Items marked provisional above are assumptions made to keep the story testable. Decided and no longer open: the volume is the player's own level and is remembered together with Mute between launches; Next with Repeat one moves to the following track.
1. Keyboard shortcuts for these controls.
2. Confirmation that Previous on the first track goes to the last track when Repeat is on and does nothing when Repeat is off, and that with Shuffle on Previous steps back through the order being played. This is the current reading of the owner's answer and is pending confirmation.
3. What Previous does in the first moments of a track (restart the track, or go to the preceding track) and how many seconds that window is.
4. How fine the position control is (step size).
5. What Next does at the end of a playlist with Repeat off. Provisionally playback ends, matching playlist playback.
6. Which window shows these controls when a single audio file is playing.

## Constraints

- Runs on macOS 26 and later.
- Every control here must also be available through AppleScript, using the action names play, pause, stop, seek, next, previous, volume and mute (covered in the AppleScript story).
- Controls follow the native look and feel requirements of the design story.
- The playlist order, shuffle and repeat rules are those of the playlist playback story.
- The saved volume and Mute state belong to the app's own settings and must be available before the first window is shown, so the controls never show a wrong level on launch.

## Out of scope

- Keyboard shortcuts (open question 1).
- Crossfade, equaliser, playback speed and any other extra control.
- Changing the Mac's system volume or the choice of output device.
- The layout and look of the controls, and which window hosts them for a single file.
- Playlist order, shuffle and repeat behaviour themselves (playlist playback story).
- Behaviour when a file cannot be read, or the output device disappears while playing (accepted gaps recorded elsewhere).

