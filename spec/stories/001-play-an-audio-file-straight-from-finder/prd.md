# PRD

Open an mp3, wav or m4a file from Finder, the app icon or the File menu and hear it immediately.

## Problem

People who keep audio files on their Mac cannot simply double-click one and hear it. Music (formerly iTunes) imports the file into a library, opens a heavy window and is slow to start. Other players expose dozens of controls and settings that a person who only wants to hear a file never needs. The person's actual job is one step: 'play this audio file'. Today that takes several steps and a lot of visual noise.

## Solution

The app is the default way to open mp3, wav and m4a files. Double-clicking such a file in Finder, dragging it onto the app icon, or choosing it from the File menu opens the app and starts playing that file at once, with no import step and no setup. If something is already playing, the newly opened file takes over. If a file cannot be played because its type is not supported, the person is told it is not supported yet and why, so they are never left wondering whether the app is broken. This resolves the multi-step and noisy experience described above.

## User Experience

## Golden path
1. The person double-clicks `song.mp3` in Finder.
2. The app opens (or comes to the front if it is already running) and the file starts playing straight away.
3. The person can see which file is playing and has the standard playback controls (their behaviour is defined by the story about controlling playback). Which window shows this is not decided yet; see Open questions.

The same result happens when the person drags the file onto the app icon in the Dock or Finder, or chooses File > Open and selects the file.

## Alternate flows
- **Something is already playing:** the new file replaces it. The previous file stops; the new one starts from the beginning. There is no confirmation question and no queue.
- **Unsupported file type:** playback does not start. The person sees a short message saying the file type is not supported yet and explaining why (for example: 'This file type is not supported yet. LocalPlayer currently plays MP3, WAV and M4A files.'). The message has one dismiss action. Anything that was already playing keeps playing.
- **No audio output available:** the system reports no output device. Nothing plays. The app does not try to work around this.
- **A playlist file is opened instead of an audio file:** it is handled by the playlist stories, not by this story; opening it never goes through the unsupported-file message.

## Empty and error states
- Empty state: when the app is launched without a file, there is no file playing. What the person sees at launch is decided by the launch story.
- Error state: the unsupported-file message above. Handling of a file that has a supported type but cannot be decoded (corrupt) when opened on its own is intentionally not specified yet. This is a recorded, accepted gap.

## Structure
No import dialog, no library prompt, no preferences prompt and no first-run wizard appear in this flow. The File menu contains an Open item.

## Behaviour
- Opening a file never changes any playlist and never copies the file.
- Opening several files at once is not specified by this story.

## Explicit non-behaviours
- Does not ask the person to import, add to a library or confirm.
- Does not queue the new file behind the current one.
- Does not play video files, FLAC, or any type other than mp3, wav and m4a.
- Does not modify, move or copy the opened file.

## Supported formats

> Anchor: `prd.open.formats`

THE SYSTEM SHALL play audio files of type mp3, wav and m4a.

## Open by double-clicking in Finder

> Anchor: `prd.open.finder`

WHEN the person double-clicks a supported audio file in Finder THE SYSTEM SHALL open the app, or bring it to the front if it is already running, and start playing that file.

## Open by dragging onto the app icon

> Anchor: `prd.open.drag`

WHEN the person drags a supported audio file onto the app icon THE SYSTEM SHALL start playing that file.

## Open from the File menu

> Anchor: `prd.open.menu`

WHEN the person chooses a supported audio file from the File menu Open item THE SYSTEM SHALL start playing that file.

## New file replaces current playback

> Anchor: `prd.open.replace`

WHILE a file is playing WHEN the person opens a different supported audio file THE SYSTEM SHALL stop the current file and start playing the newly opened file from its beginning.

## Unsupported file notice

> Anchor: `prd.open.unsupported`

WHEN the person opens a file whose type is not supported THE SYSTEM SHALL display a message stating that the file type is not supported yet and why, and SHALL leave any current playback unchanged.

## No audio output device

> Anchor: `prd.open.nodevice`

WHILE the system reports no audio output device WHEN the person opens a supported audio file THE SYSTEM SHALL NOT play audio.

## Opened files are left untouched

> Anchor: `prd.open.untouched`

IF the person opens an audio file THEN THE SYSTEM SHALL NOT copy, move, import or modify that file.

## Acceptance criteria

After this is built, the person can play an mp3, wav or m4a file by double-clicking it, dropping it on the app icon, or choosing it from the File menu, and can tell at once when a file is not supported. A non-technical person can verify each of these by hand:
1. Double-click an mp3 in Finder: the app opens and the file starts playing without any question.
2. Do the same with a wav and an m4a file: each plays.
3. Drag an mp3 onto the app icon: it plays.
4. Choose File > Open and pick an m4a: it plays.
5. While one file plays, double-click a different supported file: the first stops and the second plays from its beginning.
6. Double-click a .flac file: a message says the file type is not supported yet and why, and nothing starts. If a file was already playing it carries on.
7. Open a file with no sound output connected: nothing plays.
8. After playing a file, look at it in Finder: it is in the same place, with the same size and modification date, and no copy has appeared anywhere.

## Constraints

- Runs on macOS 26 and later.
- Distributed as a signed, notarized download outside the Mac App Store; not sandboxed.
- Everything in this story must also be controllable by AppleScript (covered in the AppleScript story).
- Performance targets for launch are covered in the launch-speed story.

## Open questions

These are not decided and are deliberately not answered here.
1. Which window shows a single opened audio file that is not part of any playlist. The app has one window per playlist and no main window, so a file opened on its own has no obvious home. Whatever is decided must keep the person's first action 'double-click and hear it' unchanged.

## Out of scope

- Playlists, shuffle and repeat (separate stories).
- Playback controls such as pause, seek, next, previous and volume (separate story about controlling playback).
- Which window shows the playing file (open question above).
- Formats other than mp3, wav and m4a, including video files.
- Behaviour when a supported-type file is corrupt and opened on its own.
- Behaviour when the audio output device changes during playback.
- Opening several files at once.
- Anonymous usage feedback about unsupported files (roadmap).

