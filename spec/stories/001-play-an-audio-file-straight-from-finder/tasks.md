# Tasks

| # | Title | Status | Type | Implements |
|---|-------|--------|------|------------|
| 1 | Create the LocalPlayer SwiftPM package and declare mp3, wav and m4a document types | proposed | implementation | open.association.register |
| 2 | Implement FormatClassifier for mp3, wav and m4a | proposed | implementation | open.format.classify |
| 3 | Implement PlaybackEngine protocol and AVFoundation engine with replace-on-play | proposed | implementation | playback.engine.play_file |
| 4 | Implement the notice mechanism (unsupported-file notice and save-failed notice) | proposed | implementation | open.unsupported.notice |
| 5 | Implement OpenCoordinator, the open-files event and File > Open | proposed | implementation | open.entry.receive |
| 6 | Guarantee the open path only reads user files | proposed | implementation | open.file.read_only |
| 7 | Unit tests: format classification boundaries | proposed | test:unit | open.format.classify |
| 8 | Unit tests: playback engine state and results | proposed | test:unit | playback.engine.play_file |
| 9 | Unit tests: classifier and engine open files read-only | proposed | test:unit | open.file.read_only |
| 10 | Integration tests: built bundle declares the three audio types plus the playlist document type | proposed | test:integration | open.association.register |
| 11 | Integration tests: engine replace and no-output-device with a recording sink | proposed | test:integration | playback.engine.play_file |
| 12 | Integration tests: unsupported notice shows once and dismisses | proposed | test:integration | open.unsupported.notice |
| 13 | Integration tests: OpenCoordinator across surface, type and prior state | proposed | test:integration | open.entry.receive |
| 14 | Integration tests: opened files are byte-identical and never copied | proposed | test:integration | open.file.read_only |
| 15 | E2E tests: document types route real Finder opens and drops to the app | proposed | test:e2e | open.association.register |
| 16 | E2E tests: unsupported file shows the real notice | proposed | test:e2e | open.unsupported.notice |
| 17 | E2E tests: opening from Finder, icon drop and File > Open in the real app | proposed | test:e2e | open.entry.receive |
| 18 | Integration tests: playlist hand-over from OpenCoordinator | proposed | test:integration | open.entry.receive |
| 19 | Unit tests: Notice enum text for unsupported and saveFailed | proposed | test:unit | open.unsupported.notice |

## Details

### 1. Create the LocalPlayer SwiftPM package and declare mp3, wav and m4a document types

Scaffold the SwiftPM package (macOS 26 platform, Swift 6 toolchain) and an Info.plist whose CFBundleDocumentTypes lists public.mp3, com.microsoft.waveform-audio and public.mpeg-4-audio with role Viewer. The playlist document type is added by the playlist-management story; this story's contract is that the final set is the three audio types plus that playlist document type and nothing else. Do not set system default handlers in code. Package layout follows the proposed paths in the design. Verify with TC-39.

### 2. Implement FormatClassifier for mp3, wav and m4a

Implement FormatClassifying per the design: content type first, extension fallback, case-insensitive, never throws; nonexistent, directory and unreadable inputs return unsupported(fileNotReadable). Content type vs extension disagreement is deliberately unspecified; do not invent behaviour. Verify with TC-30 to TC-33.

### 3. Implement PlaybackEngine protocol and AVFoundation engine with replace-on-play

Implement PlayResult and PlaybackEngine with only play(_:), stop() and isPlaying; pause, resume, seek, position, duration, volume and mute belong to the 'Control playback' story, which extends the same protocol, so write the engine and its test doubles so those additions are easy. play() stops any current file and starts the new one from 0:00; returns noOutputDevice when the system has no default output device (read from the system, not inferred from errors); returns failed and leaves prior playback untouched when a supported file cannot be started; state returns to Idle when a file finishes. Add an injectable audio sink so tests can record output. No allocations in any render callback the engine owns. Verify with TC-34 to TC-37 and TC-51.

### 4. Implement the notice mechanism (unsupported-file notice and save-failed notice)

Implement the Notice enum (unsupported(UnsupportedReason), saveFailed(String)) and NoticePresenting.show(_ notice: Notice) using a standard macOS alert sheet. The unsupported text says the file type is not supported yet and why, naming MP3, WAV and M4A, with a single dismiss action; the saveFailed text says the change could not be saved and includes the supplied reason, never the unsupported wording. At most one notice at a time and a second replaces the first. It must not touch playback. Later stories add cases to the enum. Verify with TC-38, TC-41 and TC-42.

### 5. Implement OpenCoordinator, the open-files event and File > Open

Wire the application open-files event (Finder double-click, drop on icon) and a File > Open menu item with an open panel (audio files only) to one OpenCoordinator.open(url). The init gains playlists: PlaylistOpening? = nil. PlaylistOpening (defined here) has canOpen(_:), open(_:) and endActivePlayback(). When the handler is set and the URL is a playlist document, hand it to that handler before any audio classification. For a supported audio file with a handler set, call endActivePlayback() once, before the engine play call, so a playing playlist cannot advance under the new file; unsupported files and playlist URLs never trigger it. When the handler is nil, a playlist URL is classified like any other file and endActivePlayback() is never called. Supported means engine.play; unsupported means notice and no engine call; cancel and empty lists do nothing. Multiple simultaneous URLs and which window shows a single audio file are deliberately unspecified. No playlist or disk side effects. Verify with TC-01 to TC-24, TC-43 to TC-46 and TC-52 to TC-54.

### 6. Guarantee the open path only reads user files

Audit and constrain the classifier and engine so files are opened read-only: no copy into an app library, no move, no write, no metadata or modification-time change. No runtime guard is required; the guarantee is enforced by the TC-40 and TC-53 tests. Fix any code path that violates it.

### 7. Unit tests: format classification boundaries

Cover TC-30 (uppercase extension), TC-31 (no extension, mp3 content type), TC-32 (double extension a.flac.mp3), TC-33 (empty path, directory, nonexistent file returns fileNotReadable). Positive: mp3, wav, m4a classify as supported. Negative: flac classifies as unsupported unknownType. Use real encoded fixtures, not byte stubs.

### 8. Unit tests: playback engine state and results

Cover TC-34 (second play replaces first, state Playing with second only), TC-35 (no output device returns noOutputDevice, stays Idle), TC-36 (finish returns to Idle), TC-37 (unstartable supported file returns failed, prior state unchanged). Assert state before and after each call, using a recording sink and a stubbed device-presence provider.

### 9. Unit tests: classifier and engine open files read-only

Assert that the file-opening helpers used by the classifier and engine request read-only access (inspect the open mode passed to the file layer), for supported and unsupported inputs. Negative: no write, create or rename call is made. Supports TC-40.

### 10. Integration tests: built bundle declares the three audio types plus the playlist document type

TC-39: read the built bundle Info.plist and assert CFBundleDocumentTypes declares exactly public.mp3, com.microsoft.waveform-audio and public.mpeg-4-audio (role Viewer) plus the playlist document type declared by the playlist-management story, and no other types. Negative: no flac or video types declared. Until the playlist type exists in the bundle, the test's expected set is the three audio types plus the playlist type and it is marked as depending on that story.

### 11. Integration tests: engine replace and no-output-device with a recording sink

Using real fixture files and a recording sink: play an mp3 then a wav and assert the sink shows the first stopped and the second started at 0:00; TC-51 no output device makes no sink call and does not crash. Cover all three supported formats as the new file.

### 12. Integration tests: unsupported notice shows once and dismisses

TC-38: show the unsupported notice twice in a row and assert only one is visible and dismiss closes it. TC-41: show saveFailed with the text 'could not be saved' and assert exactly one notice with that text and a dismiss action and no unsupported wording. TC-42: show an unsupported notice then a saveFailed notice without dismissing and assert the second replaces the first. TC-50: with a file playing, trigger the notice and assert playback state and position are unchanged. Assert the unsupported text names MP3, WAV and M4A and says not supported yet.

### 13. Integration tests: OpenCoordinator across surface, type and prior state

Implement the integration rows of the TC-01 to TC-24 matrix (surface x type x prior state) by calling the real open-files handler and a stubbed open panel against the real classifier and a recording engine sink, with no playlist handler configured. Plus TC-53 (no playlist change) and TC-54 (cancelled panel changes nothing). Use real encoded fixtures. The playlist hand-over cases TC-43 to TC-45 are covered by their own task.

### 14. Integration tests: opened files are byte-identical and never copied

TC-40: open each of the mp3, wav and m4a fixtures then compare checksum, size, modification time and location before and after, and assert no copy exists in the app support directory. TC-53: no playlist created or modified.

### 15. E2E tests: document types route real Finder opens and drops to the app

E2E-1 and E2E-2 against the built, signed app bundle: open -a LocalPlayer song.mp3 from a cold start, and drop a file on the app icon while another plays. Assert the app is offered for all three types and audio starts for the expected file.

### 16. E2E tests: unsupported file shows the real notice

E2E-4: open a real .flac with the built app and assert the notice appears saying the type is not supported yet and why, and that no audio starts. Repeat while another file is playing and assert playback continues.

### 17. E2E tests: opening from Finder, icon drop and File > Open in the real app

E2E-1 to E2E-3 and the e2e rows TC-01, TC-09 and TC-17 (mp3, idle) plus TC-52 (no import dialog, library prompt or confirmation appears). Drive the built app via open, Apple events and UI automation; File > Open chooses song.m4a.

### 18. Integration tests: playlist hand-over from OpenCoordinator

TC-43: coordinator built with no playlist handler, given a playlist document URL, falls through to classification so the unsupported notice is shown and nothing else changes. TC-44: coordinator built with a recording PlaylistOpening stub, given a playlist document URL, calls the stub's open once before classification and calls neither classifier, engine nor notice presenter. TC-45: same coordinator given an mp3 URL does not call the stub's open and plays as in TC-01. TC-46: same coordinator given in turn a supported audio URL, an unsupported URL and a playlist document URL: endActivePlayback() is called exactly once, for the supported URL and before the engine play call, and never for the other two; with no handler configured it is never called. Use real fixture files and a real playlist-extension file.

### 19. Unit tests: Notice enum text for unsupported and saveFailed

Unit-test the text built for each Notice without presenting anything: unsupported(unknownType) and unsupported(fileNotReadable) say not supported yet, give the reason and name MP3, WAV and M4A; saveFailed('disk full') contains 'could not be saved' and 'disk full' and none of the unsupported wording; an empty saveFailed reason still yields the 'could not be saved' text. Supports TC-38, TC-41 and TC-42.

