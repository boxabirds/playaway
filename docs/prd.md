# LocalPlayer — Product Requirements

Status: draft from spec-coach session, 2026-10-04. "LocalPlayer" is a working name taken from the directory; the product name is undecided.

## Problem

People who keep audio files on their Mac have no good way to play them. iTunes/Music is bloated and hostile to local files. The alternatives are built for power users: they expose dozens of controls, settings and panes the person doesn't need. Someone who wants to double-click a file and hear it, or keep a few playlists, ends up fighting the tool.

## Product vision

A native macOS audio player that plays local files and manages playlists, and nothing else. It opens instantly, shows only what the job needs, and looks like Apple's own design team made it.

Three qualities define it. Each is only a goal until it has a measurable threshold, and the thresholds are in the stories below.

- **Fast.** Launches into the playlist window in under one second, like Apple Notes does.
- **Simple.** Every element on screen exists for a job the user is doing. Nothing is there "because it might be useful".
- **Beautiful.** Fully compliant with Apple's Human Interface Guidelines, with Liquid Glass used at deliberate points.

## Solution overview

- A native Swift app for macOS 26 and later.
- A document-based Mac app: each playlist is a document with its own window. There is no main window and no playlist list.
- Plays local `.mp3`, `.wav` and `.m4a` files.
- Opens files from Finder (double-click, drag onto the icon) and from the File menu.
- Standard playback controls: play, pause, stop, seek, next, previous, volume and mute.
- Plays playlists with shuffle and repeat controls.
- Playlists are ordinary documents in a new file format. The person chooses where they are saved (the Save panel offers Documents by default). Deleting a playlist is done in Finder; the app does not offer it. Users who want backups keep them in iCloud Drive.
- Fully scriptable with AppleScript: every app-specific UI function has an AppleScript equivalent.
- Distributed outside the Mac App Store, signed and notarized, with updates delivered through Sparkle.

## Users and jobs

One kind of user: someone with a local audio collection who finds iTunes/Music rubbish and other players too geeky. Jobs, in order of value:

1. Play this audio file.
2. Play all the files in this playlist.
3. Create and manage playlists.

## User stories

In this document "file" means an audio file.

### US-1: Play a file

As a user, I want to play a file straight from Finder so I hear it without setting anything up.

- I can start playback three ways: double-click the file (the app is registered as the handler for supported types), drag it onto the app icon, or choose it from the File menu.
- The app opens and starts playing the file.
- Supported formats are `.mp3`, `.wav` and `.m4a`.
- If something is already playing and I open another file, the new file starts playing.
- If a file isn't supported, the app tells me it isn't supported yet and says why.
- A file that can't be read by standard audio reading tools is treated as corrupt. Inside a playlist it is skipped and marked with a hazard icon.
- When the system has no audio output device, nothing plays. The app relies on the system's reported output device.

### US-2: Play a playlist

As a user, I want to play a whole playlist, with a choice of how it plays.

- Starting a playlist plays its files in order, and the next file starts when the current one finishes.
- There are two separate controls, as in Spotify:
  - **Shuffle** is an on/off toggle.
  - **Repeat** is a button that cycles through off, all, one.
- The last-used shuffle and repeat settings persist across launches. They decide whether a playlist starts from the top or at a random track.
- Double-clicking a playlist file in Finder opens it as a document in its own window:
  - starts the playlist, from the top or at random per the last-used setting
  - if the playlist is already open, brings its window to the front (no second window) and starts playback
  - if that playlist is already playing, brings it to the front and leaves playback unchanged
- Only one thing plays at a time: starting a playlist or opening a file ends any other playback.
- Double-clicking a track in a playlist window plays that track.

### US-3: Manage playlists

As a user, I want to create and maintain playlists.

- I can create, open and rename playlists, as with any document. New Playlist opens an untitled playlist; the first save uses the standard Save panel, offering Documents by default. Later changes save automatically.
- I can add files to a playlist, remove them, and reorder them.
- Deleting a playlist is not offered; it is done in Finder.
- A playlist is a file in a new, app-specific format. Format design is out of scope for this document.
- Whether the same track may appear twice in one playlist is not decided.

### US-4: Recover missing files

As a user, I want playlists to survive moved and deleted files.

- A playlist tracks its files in a way that survives them being moved (Apple aliases, as the working choice). The playlist document updates itself when a reference is refreshed or a file is located.
- A file that has been deleted or can't be found is greyed out and not playable. Automatic play-through skips it and marks it with the hazard icon.
- I can choose "locate" on a missing file and point to its new location.
- After I locate one file, the app searches that file's folder for other missing files from the same playlist, matching on filename.

### US-5: Launch fast

As a user, I want to use the app the moment I open it.

- The first window is visible within 1 second of launch on an M2 MacBook Air. Which window that is, when there is nothing to restore, is open (proposal: an untitled new playlist).
- Open: whether that figure is for a cold launch (after reboot) or a warm one. Notes launches about 1 second slower cold than warm, so the answer decides how hard the target is.
- Open: a number for pressing play to first sound. "Super responsive to play" is the stated goal and has no threshold yet.

### US-6: See only what's needed

As a user, I want a window with nothing on it that I don't need.

- A playlist window contains only elements that serve the three jobs above.
- Open: the actual list of elements and which job each serves. This is the test for "simple", and it doesn't exist yet.

### US-6a: Control what is playing

As a user, I want the standard controls for what is playing.

- Play, pause, stop, seek, next, previous, volume and mute.
- Volume is the app's own level, and volume and mute are remembered across launches.
- Next always moves to the following track, even with repeat one.
- Previous on the first track: goes to the last track when repeat is on, does nothing when repeat is off, and steps backward through the shuffle order when shuffle is on (interpretation of the owner's words, pending confirmation).
- Open: keyboard shortcuts and what "previous" does early in a track.

### US-7: Beautiful, native look

As a user, I want the app to feel like part of macOS.

- The app complies with Apple's Human Interface Guidelines.
- Liquid Glass is used on selected surfaces.
- Open: which surfaces get Liquid Glass, and what the UI does with Reduce Transparency enabled.

### US-8: Scriptable with AppleScript

As a user, I want to control the app from AppleScript.

- Every app-specific UI function has an AppleScript equivalent, including Check for Updates. The standard menu items macOS provides (About, Quit, Hide, Services, Window, Help) are excluded from this rule.
- Regression tests cover both the UI path and the AppleScript path for every function.

### US-9: Update automatically

As a user, I want the app to keep itself up to date.

- The app checks for updates through Sparkle and lets me install them.
- There is a "Check for Updates…" menu item.
- Updates are delivered only to Macs running macOS 26 or later.
- The app never asks a separate question about whether to check for updates automatically.
- See `tech-architecture.md`.

## Constraints

- **Platform:** macOS 26 and later (Liquid Glass requires it). No fallback for macOS 15 or earlier.
- **Distribution:** direct download via DMG, Developer ID signed, notarized. Not sandboxed, not on the Mac App Store.
- **Backups:** the user's responsibility. Playlists are local files, and users back them up by storing them in iCloud Drive.
- **Language:** native Swift.

## Out of scope for v1 / roadmap

- Opt-in anonymous usage feedback, including capturing unsupported-format events through a lightweight feedback service or an Apple-provided one. It needs a consent flow and a backend, and it doesn't serve the three jobs.
- Formats beyond `.mp3`, `.wav` and `.m4a`. Video files (`.mp4`) are not in scope.
- Interoperable playlist formats such as `.m3u`.

## Accepted risks

These were considered and deliberately left unspecified.

- A playlist where every track is corrupt, on repeat, skips in a tight loop. No requirement.
- Corrupt-file handling beyond "can't be read, skip with hazard icon" is deferred. A file that fails partway through playback, and a corrupt file opened directly from Finder, are unspecified.
- Output-device changes during playback (headphones unplugged, AirPods leave the case) are unspecified.
- Missing-file matching is by filename only. Two files with the same name in the folder are not handled.

## Open questions

1. The cold/warm definition and a play-latency number (US-5).
2. The main-window element list (US-6).
3. Which surfaces get Liquid Glass, and the Reduce Transparency behavior (US-7).
4. VoiceOver and keyboard-only use. Asked three times, no answer yet.
5. Whether "once" is a state of the repeat button or just means repeat is off. The mapping above assumes repeat off.
6. The increments: which slice ships first, and what "done" means for each. The spec is currently one product.
7. Who implements it (coding agent, human, pair), what the blast radius is, and what must not be touched.
8. Product name, bundle identifier and the playlist file extension.
9. Which window appears on a launch with nothing to restore, and which window hosts playback of a single opened audio file.
10. Keyboard shortcuts, and the behavior of "previous" early in a track.
11. Whether the same track may appear twice in one playlist.

## Decisions recorded in this revision

- Playlists are documents with their own windows; there is no main window (not an SDI app).
- The person chooses where a playlist is saved; Documents is the default.
- Playback controls, including volume and mute, are in scope. Volume is the app's own level and is saved.
- A playlist document updates itself (refreshed references, located files).
- Deleting a playlist is not a feature.
- Only one thing plays at a time. A missing track reached during play-through is skipped and marked with the hazard icon.
- Shuffle toggled mid-song keeps the current track; next with repeat one moves on; double-clicking a track plays it.
- AppleScript error numbers 1001 to 1008 are accepted for now.
