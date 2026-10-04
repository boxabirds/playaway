# PRD

Double-click a playlist in Finder and it opens in its own window and plays, respecting the last-used shuffle setting and never disturbing a playlist that is already playing.

## Problem

A person who has built a playlist wants to start it the same way they start a single song: by double-clicking it in Finder. Today, in other players, that either opens a library window and waits for the person to press play, restarts music that was already playing, or opens a second copy of a playlist that is already open. Each of these is friction and noise for someone whose job is simply 'play this playlist'.

## Solution

Each playlist is an ordinary document that opens in its own window, like a document in any other Mac app. Double-clicking a playlist file in Finder opens the app, shows that playlist in its own window and starts playing it at once. Where it starts follows the person's own last-used shuffle choice: from the first track when shuffle is off, or from a random track when shuffle is on. If the playlist is already open its existing window simply comes to the front and, if it was not playing, it starts; if it is already playing it comes to the front and the music carries on without a hiccup. If the person opens a different audio file while a playlist plays, that file takes over, as it does for any single file. This removes the extra steps, the surprise restarts and the duplicate windows described above.

## User Experience

## Golden path
1. The person double-clicks a playlist file in Finder.
2. The app opens, or comes to the front if it is already running, and shows that playlist in its own window.
3. Playback starts immediately. With shuffle off it starts at the first track; with shuffle on it starts at a randomly chosen track. The shuffle and repeat controls show the settings the person last used.

## Alternate flows
- **The playlist is already open but nothing is playing:** its existing window comes to the front and the playlist starts, as in the golden path. No second window appears.
- **The playlist is already playing:** its window comes to the front. Music, position, shuffle and repeat are exactly as they were. Nothing restarts.
- **A different audio file is opened while the playlist plays:** that file replaces the playlist playback and plays from its beginning (behaviour defined in the story about playing a file from Finder).
- **A different playlist is playing and this one is double-clicked:** this playlist's window comes to the front and this playlist starts; the other playlist stops. Only one thing plays at a time.
- **Other playlist windows:** every playlist has its own window. Opening one never closes or moves the others.

## Empty states
- **A playlist with no tracks:** it opens in its own window showing the empty playlist and nothing plays. Anything that was already playing keeps playing. No message wording is specified yet; this is a provisional minimum pending an owner decision, because the empty-playlist experience belongs to the story about managing playlists.

## Error states
- **A playlist file that cannot be read** (damaged, missing, or made by a newer version of the app): no playback starts, anything already playing keeps playing, and the app does not close. Whether a message is shown, and its wording, is not decided yet. This is a provisional minimum pending an owner decision.
- Unsupported audio files are handled by the story about playing a file from Finder.

## Structure
No new screens, dialogs or prompts. There is no main window and no list of playlists: each playlist is its own document window, shown or brought forward.

## Behaviour
- Starting a playlist from Finder uses the last-used shuffle setting. It does not change that setting.
- Starting a playlist from Finder never creates a second window for the same playlist.
- Only one thing plays at a time: starting a playlist ends any other playlist or file that is playing.
- The playlist keeps its links to audio files up to date by itself, which can update the saved playlist file; the person's name, tracks and order are never changed by opening it.

## Explicit non-behaviours
- Does not ask the person to confirm.
- Does not restart a playlist that is already playing.
- Does not change the saved shuffle or repeat settings.
- Does not change the playlist's name, tracks or order.
- Does not let two things play at once.

## Double-clicking a playlist starts it

> Anchor: `prd.plopen.start`

WHEN the person double-clicks a playlist file in Finder THE SYSTEM SHALL open the app, or bring it to the front if it is already running, show that playlist in its own window, and start playing that playlist.

## Start from the top when shuffle is off

> Anchor: `prd.plopen.first`

WHILE the last-used shuffle setting is off WHEN the person double-clicks a playlist file THE SYSTEM SHALL start playing from the first track of the playlist.

## Start at a random track when shuffle is on

> Anchor: `prd.plopen.random`

WHILE the last-used shuffle setting is on WHEN the person double-clicks a playlist file THE SYSTEM SHALL start playing from a randomly chosen track of the playlist.

## Already-open playlist comes to the front and starts

> Anchor: `prd.plopen.front`

WHILE the playlist is already open and is not playing WHEN the person double-clicks that playlist file THE SYSTEM SHALL bring its existing window to the front, start playing the playlist, and SHALL NOT open a second window for it.

## Already-playing playlist is left alone

> Anchor: `prd.plopen.nodisturb`

WHILE the playlist is already playing WHEN the person double-clicks that playlist file THE SYSTEM SHALL bring its window to the front and leave the current track, position, shuffle and repeat unchanged.

## Opening an audio file replaces playlist playback

> Anchor: `prd.plopen.replace`

WHILE a playlist is playing WHEN the person opens a different supported audio file THE SYSTEM SHALL stop the playlist and start playing the opened file from its beginning.

## Shuffle and repeat settings are not changed

> Anchor: `prd.plopen.settings`

IF the person starts a playlist by double-clicking it in Finder THEN THE SYSTEM SHALL NOT change the saved shuffle or repeat settings.

## Unreadable or empty playlist leaves playback alone

> Anchor: `prd.plopen.unreadable`

WHEN the person double-clicks a playlist file that has no tracks or cannot be read THE SYSTEM SHALL NOT start playback and SHALL NOT stop anything that is already playing.

## Opening never changes the playlist's content

> Anchor: `prd.plopen.content`

IF the person opens a playlist by double-clicking it in Finder THEN THE SYSTEM SHALL NOT change the playlist's name, tracks or order.

## Constraints

- Runs on macOS 26 and later.
- Distributed as a signed, notarized download outside the Mac App Store; not sandboxed.
- Must also be controllable by AppleScript (covered in the AppleScript story).
- Launch speed targets are covered in the launch-speed story.
- The playlist is an ordinary document with its own window; there is no main window and no playlist list.

## Out of scope

- The playlist file format, its file extension, the Finder registration of playlist files and how playlists are created, saved and edited (story about managing playlists).
- Shuffle and repeat behaviour during playback, and what is played first under shuffle (story about playing a playlist).
- The wording and presentation of any message for an empty or unreadable playlist.
- Opening several playlist files at once.
- Missing audio files inside a playlist (separate story).
- What happens to playback when the window of a playing playlist is closed.

## Open questions

These are not decided and are deliberately not answered here.
1. Which window hosts playback of a single audio file opened from Finder, now that there is no main window.
2. What the person sees when a playlist is empty or cannot be read.

Decided by the owner: only one thing plays at a time, so starting a playlist stops any other playlist or file that is playing.

