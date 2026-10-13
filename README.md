# LocalPlayer

A fast, simple, native macOS 26 player for local **mp3, wav and m4a** files. Double-click a file and it plays; keep
playlists as ordinary documents you can see in Finder; shuffle, repeat, volume and mute that remember how you left them;
everything the windows and menus do can also be done from AppleScript.

**Status: in development, not released.** The app builds and runs from source and has a large automated test suite, but
no signed or notarized build has been published yet (see [Not done / not verified](#not-done--not-verified)).

## Highlights

- **Open anything fast.** Finder double-click, drop on the Dock icon or File > Open Audio File all start playback at
  once, with no import step and no library. Files are never copied or modified.
- **Playlists are documents.** One window per playlist, saved where you choose (Documents by default), autosaved in place
  with atomic writes, undo and redo, drag to reorder, drop files in from Finder.
- **Playlists survive moving files.** Tracks follow files that move; missing ones are greyed out and skipped with a
  hazard icon; Locate reconnects a whole folder of missing tracks in one step.
- **Shuffle and Repeat (off, all, one)** are independent, shared, and restored on launch. Volume and mute are the
  player's own level, kept across launches, and never touch the Mac's system volume.
- **Scriptable end to end.** 19 actions, one AppleScript dictionary, numbered errors, and a build gate that refuses a
  release if any on-screen action lacks a script equivalent.
- **Updates via Sparkle**, never delaying the first window.

## Requirements

macOS 26 or later, Xcode 27 / Swift 6.2 toolchain. Sparkle is fetched by SwiftPM.

## Where this comes from

The behaviour is specified in [`spec/`](spec) (11 stories with requirements, designs and test plans; start at
[`spec/README.md`](spec/README.md)); the product and architecture drafts are in [`docs/`](docs).

## Build and test

```
swift build                       # debug build
swift test                        # unit + integration + e2e (e2e skip unless the dev bundle exists)
scripts/run-e2e.sh                # builds a separate ad-hoc signed e2e bundle (own name and id), runs e2e against it
scripts/bundle-dev.sh [release]   # .build/dev-app/LocalPlayer.app (ad-hoc signed, for development only)
scripts/build-app.sh              # release pipeline: universal, Developer ID, notarize, DMG (see "Not done")
scripts/release.sh                # version bump, appcast, publish (aborts while placeholders remain)
scripts/launch-bench.sh           # repeatable first-window launch timing
scripts/check-min-os.sh           # the single macOS-floor consistency check
scripts/check-hig.sh              # the HIG review gate
```

## Layout

| Path | What |
|---|---|
| `Sources/PlayawayCore` | the module the Mac and iPhone apps share (no AppKit): model, store, resolver, relinker, decider, shuffle, player, engine, format classifier, open coordinator, transport view model, UI manifest and checker, HIG checklist. `package` access, builds for macOS and iOS |
| `Sources/LocalPlayer/Open` | notice presenter (AppKit; the format classifier and `OpenCoordinator` moved to `PlayawayCore`) |
| `Sources/LocalPlayer/Playback` | `PlaybackEngine`, `AVPlaybackEngine` (AVAudioPlayer behind an injectable sink), volume store |
| `Sources/LocalPlayer/Playlists` | model, store (atomic JSON `.lplaylist`), `PlaylistDocument` (NSDocument), decider, shuffle, player, resolver, relinker, router |
| `Sources/LocalPlayer/UI` | window controller, transport and mode controls, UI manifest + checker, glass helper, HIG checklist |
| `Sources/LocalPlayer/Scripting` | sdef-backed commands, `AppActions`, action manifest, parity gate |
| `Sources/LocalPlayer/Updates` | Sparkle wiring, config validation, self-tests |
| `Resources` | `Info.plist`, `LocalPlayer.sdef`, `ui-manifest.json`, entitlements |

## AppleScript

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

## Decisions made where the spec was silent or open

The spec says several things are undecided and must not be invented. These are the places an implementation had to
pick something anyway. Each is isolated and easy to change.

* **Single audio file window.** There is no main window. A single opened file is shown by the first group of any
  playlist window (the transport is bound to the one shared engine); if no window is open an untitled playlist
  window hosts it.
* **Play with nothing loaded** starts the front playlist, else replays the last single file, else 1002.
* **Menus.** App, File, Edit, Window, Help. Edit has Undo, Redo, Select All and Remove from Playlist (the spec left an
  Edit menu open). Add Files and Play/Pause (Space) are in File; Open Audio File is Option-Command-O.
* **Time display.** Elapsed on the left, *time remaining* on the right. (A total-length label read the same text as
  elapsed at 0:00 and macOS accessibility merged the two; found by the real-window e2e test.)
* **A file in the Trash counts as deleted** (an alias follows a file into the Trash).
* **Script `new playlist` onto an existing file** is refused (1005) rather than overwriting.
* **Window restoration** is on by default (`NSQuitAlwaysKeepsWindows` is registered, not forced).
* Provisional rules the spec itself flags (Previous on the first track, repeat one + shuffle, shared settings across
  windows, error numbers) are implemented as the spec states them.

## Not done / not verified

* **Notarization, stapling, Gatekeeper and a real release were never run** (no credentials were used, nothing was
  submitted or published). `build-app.sh` / `release.sh` are tested with recording shims and an ad-hoc signature only.
  `release.sh` refuses while the feed URL, update key, hosting project and release repo are placeholders, which they
  are on purpose: product name, bundle id (`com.localplayer.app` is a working stand-in), feed and keys are undecided.
* **The HIG checklist is fully unmarked on purpose**, so the release gate currently refuses. A reviewer has to sign
  it off; who that is, is an open question in the spec.
* **Launch timing**: measured only on this machine (debug dev bundle). Nothing is claimed about an M2 MacBook Air,
  a release build, or a true cold launch (purging the cache needs root). See `scripts/launch-bench.sh`.
* **Not automated**: the real Save panel's default folder and Open Recent clicks, drag-and-drop from Finder,
  VoiceOver and keyboard-only behaviour, glass surfaces (none are used yet), Reduce Transparency visuals,
  Sparkle's second-launch permission question on a real GUI run, scheduled (timer-driven) update checks.
* Open spec questions left open: keyboard shortcuts for transport, the first-moments rule for Previous, seek step
  size, which surfaces use glass, VoiceOver requirements, duplicate tracks in one playlist.
