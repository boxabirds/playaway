# PRD

Play every track in a playlist automatically, with independent shuffle and repeat controls whose settings are remembered.

## Problem

People who keep audio files on their Mac want to start a collection of tracks and then stop thinking about it. Music (formerly iTunes) buries playback options in menus and mixes them with a library the person never asked for. Other players present shuffle, repeat, crossfade, queues and more as equal-weight controls, so a person never knows which setting is currently on. The person's second most valuable job is 'play all the files in this playlist': it should keep playing without attention, in the order or randomness they prefer, and remember how they like it next time.

## Solution

A playlist plays from its first track to its last without any further action: when one track finishes the next starts. Double-clicking any track in a playlist plays that track at once. Two separate controls, familiar from Spotify, govern how it plays: Shuffle is an on/off switch, and Repeat is a button that steps through off, all and one. Both controls always show their current state, and the app remembers both between launches so the person never has to set them again. Starting a playlist, or playing a track from it, takes over from anything else that is playing, so only one thing plays at a time. If a track in the playlist cannot be played, either because the file cannot be read or because the file is missing, the app skips it, marks it with a hazard icon so the person can see what happened, and carries on with the next track instead of stopping the music. This resolves the buried options, the unclear current setting and the music stopping at a bad track described above.

## User Experience

## Golden path
1. The person has a playlist open in its own window and starts it.
2. The first track plays. With shuffle off that is the first listed track; with shuffle on it is the first track of a random order.
3. When a track finishes, the next one begins on its own, with no gap the person has to bridge by clicking.
4. The person can press Shuffle at any time to turn it on or off, and press Repeat to step through off, all and one.
5. After the last track, playback behaves according to the Repeat setting (stops, starts the playlist again, or replays the same track).
6. On the next launch both controls show the same state they were left in.

## Alternate flows
- **The person double-clicks a track:** that track plays from its beginning and becomes the current track. Anything else that was playing stops. With shuffle off the playlist carries on from that track in listed order. With shuffle on the remaining tracks follow in a random order after it.
- **The person double-clicks a track that is missing or cannot be read:** it does not play, it is marked with the hazard icon, and anything that was already playing carries on unchanged. This reading, that playback is left unchanged, is an interpretation pending owner confirmation.
- **Something else is already playing:** starting this playlist, or playing one of its tracks, stops it, so only one thing plays at a time.
- **Empty playlist:** there is nothing to play; starting it does nothing and no track is shown as playing.
- **A track cannot be read:** when playback reaches that track it is skipped, a hazard icon appears next to it in the list, and the next track starts.
- **A track's file is missing (moved or deleted and not found):** when playback reaches it, it is skipped, the same hazard icon appears next to it, and the next track starts. The hazard icon is added on top of the greyed-out look the missing-files story gives such a track. How missing tracks are repaired belongs to the missing-files story.
- **Single-track playlist:** with repeat off it plays once and stops; with repeat all or one it plays again.
- **First launch ever:** Shuffle is off and Repeat is off.

## Structure
- Each playlist is its own document with its own window. There is no main window and no list of playlists in this story.
- Each playlist window has a Shuffle control, showing on or off, and a Repeat control, showing off, all or one. Pressing Repeat moves to the next of the three states in that order and then back to off.
- Provisional: the two settings are shared, so every open playlist window shows the same Shuffle and Repeat state.
- Each track row can show a hazard icon.
- The two controls are separate. There is no combined mode switch.

## Behaviour
- Changing Shuffle or Repeat does not interrupt the track that is playing. Turning Shuffle on keeps the current track playing and shuffles the tracks after it; turning it off keeps the current track playing and carries on in listed order from that track.
- The setting shown on each control is the setting that is actually in effect.
- Skipping an unreadable or missing track is automatic and needs no confirmation. The hazard icon stays for the rest of the session.

## Explicit non-behaviours
- Does not change the order of tracks stored in the playlist when shuffle is on.
- Does not show a message or dialog when a track is skipped; the hazard icon is the only signal, for an unreadable and for a missing track alike.
- Does not offer crossfade, queues, or extra play modes.
- Does not play two playlists at once.
- Does not save the hazard icon into the playlist file; it is a session marker.

## Play in listed order

> Anchor: `prd.playlist.order`

WHILE shuffle is off WHEN the person starts a playlist THE SYSTEM SHALL play its tracks in the order they are listed, beginning with the first track.

## Starting a playlist takes over playback

> Anchor: `prd.playlist.start`

WHEN the person starts a playlist that has at least one track THE SYSTEM SHALL stop anything else that is playing, so that only one thing plays at a time.

## Double-clicking a track plays it

> Anchor: `prd.playlist.play_track`

WHEN the person double-clicks a playable track in a playlist THE SYSTEM SHALL stop anything else that is playing, play that track from its beginning, and make it the current track.

## Shuffle carries on after the chosen track

> Anchor: `prd.playlist.play_track_shuffle`

WHILE shuffle is on WHEN the person double-clicks a playable track THE SYSTEM SHALL continue after that track with the remaining tracks of the playlist in a random order.

## A track that cannot be played is marked, not played

> Anchor: `prd.playlist.play_track_blocked`

WHEN the person double-clicks a track whose file is missing or cannot be read THE SYSTEM SHALL NOT play it, SHALL mark it with a hazard icon, and SHALL leave anything already playing unchanged.

## Automatic advance

> Anchor: `prd.playlist.advance`

WHEN a track finishes playing and another track remains to be played THE SYSTEM SHALL start the next track automatically.

## Shuffle plays in random order

> Anchor: `prd.playlist.shuffle`

WHILE shuffle is on THE SYSTEM SHALL choose the tracks of the playlist to play in a random order.

## Shuffle is an on/off control

> Anchor: `prd.playlist.shuffle_toggle`

WHEN the person presses the Shuffle control THE SYSTEM SHALL switch shuffle between on and off and show the new state.

## Repeat steps through three states

> Anchor: `prd.playlist.repeat_cycle`

WHEN the person presses the Repeat control THE SYSTEM SHALL change repeat from off to all, from all to one, and from one to off, and show the new state.

## Repeat off stops after the last track

> Anchor: `prd.playlist.repeat_off`

WHILE repeat is off WHEN the last track of the playlist finishes THE SYSTEM SHALL stop playback.

## Repeat all starts the playlist again

> Anchor: `prd.playlist.repeat_all`

WHILE repeat is all WHEN the last track of the playlist finishes THE SYSTEM SHALL start the playlist again.

## Repeat one replays the track

> Anchor: `prd.playlist.repeat_one`

WHILE repeat is one WHEN a track finishes THE SYSTEM SHALL play the same track again.

## Shuffle and Repeat are independent controls

> Anchor: `prd.playlist.independent`

THE SYSTEM SHALL provide Shuffle and Repeat as two separate controls, so that changing one does not change the other.

## Settings are remembered

> Anchor: `prd.playlist.persist`

WHEN the app is launched THE SYSTEM SHALL restore the Shuffle and Repeat settings the person last chose, and WHERE no setting was ever chosen THE SYSTEM SHALL start with Shuffle off and Repeat off.

## Unreadable tracks are skipped and marked

> Anchor: `prd.playlist.skip_unreadable`

WHEN playback reaches a track that cannot be read THE SYSTEM SHALL skip that track, mark it with a hazard icon, and continue with the next track.

## Missing tracks are skipped and marked

> Anchor: `prd.playlist.skip_missing`

WHEN playback reaches a track whose file is missing THE SYSTEM SHALL skip that track, mark it with a hazard icon, and continue with the next track.

## Shuffle does not rewrite the playlist

> Anchor: `prd.playlist.order_untouched`

IF shuffle is on THEN THE SYSTEM SHALL NOT change the order in which tracks are stored in the playlist.

## Acceptance criteria

A non-technical person can check each of these by hand, using a playlist of five short tracks.
1. With Shuffle off, start the playlist: the first listed track plays, then the others follow in listed order with no clicks.
2. With Repeat off, let the last track finish: playback stops.
3. Press Repeat three times: it shows all, one, then off. With Repeat all, the playlist starts again after the last track; with Repeat one, the same track plays again.
4. Press Shuffle: it shows on. Start the playlist: it begins with a random track and every track plays once before the end. Open the playlist file in Finder afterwards: the listed order is unchanged.
5. Press either control while a track plays: the track keeps playing without restarting. With a track playing, turn Shuffle on: that track keeps playing and the others follow in a random order; turn it off: that track keeps playing and the next listed track follows it.
6. Quit and relaunch: Shuffle and Repeat show the same states as before. On the very first launch both show off.
7. Replace one track with a damaged file and start the playlist: that track is skipped, a hazard icon appears next to it, and the next track plays with no dialog.
8. Move one track's file out of its folder so it is missing and start the playlist: that track is skipped, a hazard icon appears next to it, and the next track plays with no dialog.
9. Start a different playlist while one is playing: the first stops and only the new one plays.
10. Start an empty playlist: nothing plays and nothing already playing changes.
11. Double-click the third track while another track plays: the third track plays from its beginning and the other track stops. With Shuffle off, the fourth track follows it. With Shuffle on, the other tracks follow in a random order.
12. Double-click a track whose file is missing while something plays: the track does not play, it shows a hazard icon, and the music carries on.

## Constraints

- Runs on macOS 26 and later.
- Each playlist is its own document with its own window; there is no main window.
- The Shuffle and Repeat controls must be controllable by AppleScript (covered in the AppleScript story).
- Fully compliant with Apple Human Interface Guidelines for the controls shown (see the design story).
- Only one playlist or file plays at a time.

## Out of scope

- Creating, editing and renaming playlists, and where they are saved (separate story). Deleting a playlist is not an app feature; people do it in Finder.
- Opening a playlist from Finder (separate story).
- The Next, Previous, pause, seek and volume controls (separate control-playback story). Only the order they step through, and the shuffle order, are shared with this story.
- How missing and moved files are detected, shown as greyed out and repaired (separate story). This story only skips a missing track while playing, with the hazard icon, and refuses to play one the person chooses.
- What a mode called 'once' means, and whether it is anything other than repeat off. This is an open question; this story treats it as repeat off.
- What happens when shuffle and repeat are both on, beyond each working independently: whether every track plays once before any repeats, and what repeat one means in shuffle. Not yet decided.
- A playlist in which every track is unreadable or missing and repeat is on. This will skip in a tight loop; recorded as an accepted risk with no requirement.
- A track that fails part-way through playing, and changes of audio output device during playback.
- Which window hosts playback when a single audio file is opened: an open question.
- Where the controls sit in the window and which glass surfaces they use.

