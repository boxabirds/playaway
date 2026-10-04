# PRD

Everything the person can do in the player's windows and menus, apart from the standard items macOS provides, can also be done from AppleScript, and tests prove both routes behave the same.

## Problem

Mac users who automate their day with AppleScript, Shortcuts or other scripting tools cannot control most audio players: the actions are only reachable by clicking. A person who wants a morning playlist to start at a set time, wants a keyboard launcher to skip a track or change the volume, or wants another app to hand the player a file has no way to do it. Where a player offers scripting at all, it often covers only a handful of actions, so scripts break the moment they need something it left out, and the scripted behaviour can quietly differ from what the buttons do.

## Solution

The player can be fully driven by AppleScript. Every action the player offers in its windows and menus, other than the standard items macOS provides, has an equivalent scripting command or property, so anything a person can do by clicking, a script can do too. That includes playing, playing a chosen track, pausing, seeking, skipping, volume and mute, shuffle and repeat, creating and editing playlists, locating a missing file, and checking for updates. A scripted action gives exactly the same result as the matching click: the same playback, the same playlist changes, the same refusals, and the same settings kept for the next launch. When a script asks for something that cannot be done, it gets a clear numbered error with a plain-language message instead of silence. The product is also protected against drift: when a new on-screen action is added without a scripting equivalent, the build is refused, and regression tests exercise every action by both routes.

## User Experience

## Golden path
The person opens Script Editor (or any tool that runs AppleScript), asks the player to open a named audio file, then to play, pause, skip to the next track, set the volume, mute, turn shuffle on, and set repeat to all. Each command does what the matching on-screen control does, and the player's window updates live to show it, so a person watching sees the script working.

The person can also ask the player to play a particular track of an open playlist by its position, which does what double-clicking that track does.

The person can also ask the player questions: whether it is playing, which track is current, how far into the track it is, the volume, whether it is muted, whether shuffle is on, and what repeat is set to. After the player is quit and opened again, the volume and mute settings are the ones that were last chosen, whether by clicking or by script.

Each playlist is a document with its own window. A script addresses a playlist by the name of the open playlist document. A script can make a new playlist (it starts as an untitled playlist, or is saved to a path the script supplies), rename a playlist, add, remove and reorder tracks, and locate a missing file. A script can also ask the player to check for updates.

## Alternate flows
- **Player not running:** a script that addresses the player launches it first, the same as opening it from Finder.
- **Nothing to act on:** asking to pause or skip when nothing is playing, or asking about a playlist that is not open, returns a numbered error and a plain message such as 'No open playlist named Morning'. Nothing changes.
- **Unsupported or missing file:** asking to open a file that is not supported, or does not exist, returns a numbered error with the same explanation the person would see on screen. Playback is not affected.
- **Missing track:** asking to play a track whose file is missing is refused in the same way as double-clicking it: nothing plays.
- **Mid-playback commands:** a script that opens another file, or plays another track, while something plays replaces it, exactly as in Finder or by double-clicking. Only one thing plays at a time.
- **Out-of-range values:** a volume outside 0 to 100, a seek time outside the track, or a track number that does not exist returns a numbered error and changes nothing.
- **Update check not available:** asking to check for updates before the update service has started returns a numbered error.

## Empty and error states
- Empty state: with no playlists open, listing playlists returns an empty list, not an error.
- Error states: every refused command reports a stable error number and a message. The refusals match what the on-screen controls refuse.

## Structure
The player has a scripting dictionary visible in Script Editor's Open Dictionary view, listing each command, object and property with a one-line description. No new window, preference or setup is added to the player for scripting.

## Behaviour
- A scripted action and its on-screen twin are indistinguishable in result.
- The window reflects scripted changes immediately.
- Reading a property never changes anything.
- Previous track and next track give the same result as the on-screen controls, including what they do at the first and last track and with shuffle or repeat on.
- The standard items macOS provides (About, Quit, Hide, Services, the Window menu and the Help menu) are not scripted by this player.

## Explicit non-behaviours
- Does not require turning on a scripting setting in the player.
- Does not offer scripting-only features that have no on-screen equivalent in this version.
- Does not add commands for actions the player's windows and menus do not have.
- Does not offer a command to delete a playlist, because deleting a playlist is done in Finder and is not a feature of the player.
- Does not run scripts, store scripts or provide a script editor of its own.

## Every on-screen action is scriptable

> Anchor: `prd.script.parity`

THE SYSTEM SHALL provide an AppleScript command or property for every action the player offers in its windows and menus other than the standard items macOS provides.

## Missing scripting equivalents are caught before release

> Anchor: `prd.script.parity_gate`

IF an on-screen action other than a standard macOS item has no matching AppleScript command or property THEN THE SYSTEM SHALL NOT pass its release build.

## Open a file by script

> Anchor: `prd.script.open`

WHEN a script asks the player to open an audio file THE SYSTEM SHALL open and play that file with the same result as opening it from Finder, including replacing any file already playing and showing the unsupported-file message for unsupported types.

## Playback commands

> Anchor: `prd.script.transport`

WHEN a script issues play, pause, stop, seek, next track, previous track, a volume setting or a mute setting THE SYSTEM SHALL perform the same action as the matching on-screen control, and for a volume or mute setting SHALL keep that setting for the next launch in the same way as the on-screen control does.

## Play a chosen track by script

> Anchor: `prd.script.play_track`

WHEN a script asks the player to play a track, by its position in an open playlist, THE SYSTEM SHALL play that track with the same result as double-clicking it in the playlist window, including replacing anything already playing and NOT playing a track whose file is missing.

## Shuffle and repeat by script

> Anchor: `prd.script.modes`

WHEN a script sets shuffle on or off, or sets repeat to off, all or one, THE SYSTEM SHALL apply the same setting as the matching on-screen control and keep that setting for the next launch.

## Playlist and track management by script

> Anchor: `prd.script.playlists`

WHEN a script makes a new playlist, renames an open playlist, adds, removes or reorders tracks in an open playlist, or locates a missing file, THE SYSTEM SHALL give the same result as the matching on-screen action.

## Check for updates by script

> Anchor: `prd.script.updates`

WHEN a script asks the player to check for updates THE SYSTEM SHALL start the same update check as the Check for Updates menu item, and WHILE the update service has not started THE SYSTEM SHALL return a numbered error instead.

## Reading player state

> Anchor: `prd.script.state`

WHEN a script reads whether the player is playing, the current track, the position in the track, the volume, whether it is muted, the shuffle setting or the repeat setting THE SYSTEM SHALL return the current value without changing any state, and after the player has been quit and opened again SHALL return the volume and mute values that were last set by any route.

## Refused commands report clearly

> Anchor: `prd.script.errors`

IF a script command cannot be carried out, such as naming a playlist that is not open, giving a volume outside 0 to 100, opening an unsupported or missing file, or pausing when nothing is playing, THEN THE SYSTEM SHALL return a numbered error with a plain-language message and SHALL NOT change playback or playlists.

## Both routes are regression tested

> Anchor: `prd.script.tested`

THE SYSTEM SHALL have regression tests that exercise every scriptable player action by both the on-screen route and the AppleScript route and confirm the results match.

## Constraints

- Runs on macOS 26 and later, as with the rest of the player.
- The player is not sandboxed, so no scripting entitlement beyond the standard system automation permission prompt is part of this story.
- Scripting coverage is defined by parity with the app-specific actions that exist, not by a fixed command list. At the time of writing there are 19: open file, play, play track, pause, stop, seek, next, previous, volume, mute, shuffle, repeat, new playlist, rename playlist, add track, remove track, reorder track, locate missing file, check for updates.
- Each playlist is a document with its own window; there is no main window and no playlist list. Scripts address playlists by the name of an open playlist document.
- Volume is expressed to scripts as a whole number from 0 to 100. Volume and mute are the player's own settings and are kept across launches, whichever route sets them.
- Only one thing plays at a time.
- Error numbers 1001 to 1008 are accepted for now and may change until the first release.
- Previous track on the first track of a playlist follows the on-screen control: it goes to the last track when repeat is on, does nothing when repeat is off, and with shuffle on it goes back through the shuffled order. This reading of the owner's answer is an interpretation pending owner confirmation.
- This story depends on the actions defined by the other stories: opening a file, playlist playback, controlling playback, playlist management, missing-file recovery and updates.

## Out of scope

- Scripting-only features with no on-screen equivalent.
- A command-line tool or any other automation route besides AppleScript.
- Deleting playlists: this is done in Finder and is not a feature of the player, so there is no scripting command for it.
- Scripting the standard items macOS provides (About, Quit, Hide, Services, the Window menu and the Help menu).
- Renaming a playlist that has never been saved: not specified.
- Behaviour when a script supplies a save path that already holds a file: not specified.
- Which window plays a single audio file that was opened on its own (open question owned by the open-a-file and playlist-document stories).
- Duplicate tracks in one playlist: undecided.
- Sandboxing or App Store scripting rules.
- Behaviour for unspecified cases already recorded in the product requirements, such as corrupt files opened alone and output-device changes during playback.

