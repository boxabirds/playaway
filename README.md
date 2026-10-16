# Playaway

[play.away.software](https://play.away.software)

A fast, simple, native player for your own **mp3, wav, m4a and flac** files, on iPhone and Mac. No library, no
import, no account: your files stay where they are. Playlists are ordinary documents you can see in Files or Finder,
and they can live in iCloud Drive so the same playlist plays on every device.

Formerly **LocalPlayer**. The Mac target, its bundle id (`com.localplayer.app`) and its AppleScript name are still
`LocalPlayer` in code; the product, the iPhone app and the repository are Playaway.

**Status (2026-10-16):** the iPhone app is on TestFlight (build 20). The Mac app builds and runs from source with a
large automated test suite; no signed or notarized Mac build has been published.

## What it does

- **iPhone.** Playlists of songs picked from the Files app, played with shuffle and repeat, a floating controller and a
  player card with a scrubber you can hear while you drag. Playlists can be moved to iCloud Drive (a top-level
  `Playaway` folder) so they travel to other devices; songs that iCloud has evicted are fetched when you play them.
  The app remembers where you were, through relaunches and kills. Lock Screen and headphone controls.
- **Mac.** Double-click a file and it plays; one window per playlist, autosaved in place, undo and redo, drag to
  reorder, drop files in from Finder. Tracks follow files that move; missing ones are greyed out and skipped; Locate
  reconnects a whole folder. Everything the windows and menus do can be done from AppleScript. Updates via Sparkle.
- **Lyrics (experiment, iPhone, off by default).** The words of a song are transcribed on the phone from the song
  itself (Apple's speech model or Whisper, optionally after separating the vocals with a Core ML model) and shown in
  time with the music when the player card is pulled up. They are machine guesses and are labelled as such. Nothing is
  looked up or uploaded. Turn it on under the flask button on the Playlists screen.

## Requirements

iOS 26 or later (iOS 27 for the Music Understanding vocal gate); macOS 26 or later; Xcode 27 / Swift 6.2. Sparkle and
WhisperKit are fetched by SwiftPM.

## Where the behaviour is specified

Stories, requirements, designs and test plans are kept in Ceetrix; snapshots and the general designs are in
[`spec/`](spec) (start at [`spec/README.md`](spec/README.md)). Product and architecture drafts are in [`docs/`](docs).

## Build and test

```
swift build                       # the Mac app and the shared modules
swift test                        # core, lyrics and Mac suites (Mac E2E tests drive the real window and need
                                  # Accessibility permission for the terminal)
PLAYAWAY_LYRICS_ENGINES=1 swift test --filter PlayawayLyricsTests   # the real speech engines, models permitting
swift run -c release lyrics-eval <folder>   # measures the lyrics engines on songs with <name>.txt lyrics (Mac)
scripts/ios-ui-tests.sh [-only-testing:...] # the iPhone UI suite in the simulator, silent
scripts/release-gate.sh           # swift test, then the whole iPhone UI suite; run before any upload
scripts/bundle-dev.sh [release]   # .build/dev-app/LocalPlayer.app (ad-hoc signed, development only)
scripts/build-app.sh              # Mac release pipeline: universal, Developer ID, notarize, DMG (never run for real)
scripts/launch-bench.sh           # repeatable first-window launch timing (Mac)
scripts/check-hig.sh              # the HIG review gate
```

The iPhone project is generated: `cd ios && xcodegen generate`, then build the `Playaway` scheme. Archive and
TestFlight upload use `xcodebuild archive` and `-exportArchive` with `ios/build/ExportOptions.plist` (not in git).

## Layout

| Path | What |
|---|---|
| `Sources/PlayawayCore` | shared by the Mac and iPhone apps, no AppKit or UIKit: playlist model and store, resolver and relinker, advance decider and shuffle, the playback engine with its audio lease (one sound at a time), the transport view model, iCloud sync logic, lyrics model and pipeline, UI manifest and HIG checklist. `package` access |
| `Sources/PlayawayLyrics` | the lyrics engines: Apple `SpeechTranscriber`, WhisperKit, the UVR MDX-Net vocal separator on Core ML with its vDSP STFT, vocal-activity gates, model downloads |
| `Sources/LyricsEval` | `lyrics-eval`, the Mac measurement of the engines on songs with known lyrics |
| `Sources/LocalPlayer` | the Mac app (AppKit): document windows, transport and mode controls, scripting, Sparkle |
| `ios/` | the iPhone app (SwiftUI with a UIKit song table), its UI tests and `project.yml` for xcodegen |
| `Tests/` | `PlayawayCoreTests`, `PlayawayLyricsTests`, `LocalPlayerTests` |
| `Resources` | Mac `Info.plist`, `LocalPlayer.sdef`, `ui-manifest.json`, entitlements |
| `scripts/` | build, test, gate and release scripts |

## AppleScript (Mac)

```applescript
tell application "LocalPlayer"
    open audio file "/path/song.mp3"
    set the volume to 50          -- NOT "set volume to 50": AppleScript's StandardAdditions claims that form
    set muted to false
    set shuffle to true
    set repeat mode to "all"      -- "repeat" is an AppleScript keyword, so the property is "repeat mode"
    new playlist at "/path/Morning.lplaylist"
    add track "/path/a.mp3" to "Morning"
    move track 3 to 1 in "Morning"
    play track 1 in "Morning"
    next track
end tell
```
Refusals come back as numbered errors: 1001 no such open playlist, 1002 nothing playing, 1003 unsupported file,
1004 file not found, 1005 invalid parameter, 1006 no such track, 1007 could not locate, 1008 not ready.

## Decisions that are not in the spec

* **One sound at a time, by construction.** The engine holds one audio lease; whatever starts a sound (a song, the
  scrub loop) silences the holder first. A source scan test fails if any sound producer appears outside the engine.
* **Playback state lives in the engine only.** Screens read it live; no view model keeps a copy of the position.
* **Scrubbing is audible.** Hold still on the slider and a one-second snippet loops from under your finger; on lift
  the song continues from where the loop was. A paused song is never started by a scrub.
* **iCloud: "in iCloud" means any iCloud Drive file.** Local playlists stay local until you confirm a move; new
  playlists are created in iCloud as `Playaway/<name>/<name>.lplaylist`; deleting removes only the playlist file.
* **Lyrics come from the audio, not a lookup.** Made on request, kept per song, labelled as a guess.
* Mac-only choices from the first version (single audio file window, Play with nothing loaded, menus, time display,
  Trash counts as deleted, script `new playlist` refuses to overwrite, window restoration on) are unchanged.

## Not done / not verified

* **Mac release never run for real**: no notarization, no DMG published; `release.sh` refuses while its feed and keys
  are placeholders. The Mac has no iCloud sync yet (no container entitlement or provisioning profile).
* **Lyrics experiment on a real phone**: speed, memory, the Make Lyrics flow end to end, the Music Understanding gate
  on iOS 27, and accuracy on sung audio are all unmeasured; the panel is tested in the simulator with a seeded sheet.
  Published speech benchmarks say nothing about singing, and Whisper is about one word in five wrong on lyrics.
* **Real-device iCloud behaviour**: moving and copying songs with a real account, and whether a bookmark made on the
  iPhone resolves on a Mac.
* **Card resize between songs with and without artwork snaps rather than slides**; a system sheet cannot slide while
  keeping the controls fixed.
* **Not automated on the Mac**: the real Save panel, Finder drag-and-drop, VoiceOver and keyboard-only use, Sparkle's
  second-launch question, scheduled update checks. The HIG checklist is unmarked on purpose.
