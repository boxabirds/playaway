# LocalPlayer for iPhone: technical design

Status: proposal. Nothing here was built, compiled or run. Written 2026-10-05 against the `main` checkout. It implements the UX in `spec/general/UI-IMPROVEMENTS.md` ("iPhone version (proposal)") and the three phone mockups in `spec/general/ui-mockups.html`. It does not change any macOS spec; where it diverges, the divergence is listed in section 13.

## 0. How to read this

- "Verified" means I read the source file or config in this repo. It does not mean I built or ran anything.
- "Unverified" means it rests on my knowledge of Apple platform APIs, with no source, header or simulator check in this session. Those items are marked "unverified" in the text, and the ones that can invalidate the design are the phase 0 spikes in section 16; each needs a spike before it is relied on.
- Effort is not estimated in days or weeks. I have no velocity data for this repo, so phases carry exit criteria only.

## 1. What the code is today (verified)

- One SwiftPM package, `Package.swift`, tools 6.2, Swift 5 language mode, `platforms: [.macOS(.v26)]`, one `executableTarget` named `LocalPlayer` (path `Sources/LocalPlayer`) depending on Sparkle, and one `testTarget` `LocalPlayerTests`.
- Every test file does `@testable import LocalPlayer`, except `MinOSConsistencyTests` and `ReleaseScriptTests`, which import only XCTest (and CryptoKit) and read scripts and plists.
- Not one declaration in the app target is `public` (a grep for `public` finds only three hits in `UpdateConfiguration.swift` and one in `UpdaterController.swift`, which I read as conformance or protocol-witness uses). Everything is module-internal. This matters for the split in section 2.
- The app is not sandboxed (`Resources/LocalPlayer.entitlements` holds only `network.client`), so `TrackReference.make` creates bookmarks with `options: []` and `TrackResolver` falls back to a plain path.
- The `.lplaylist` format is UTF-8 JSON, `{"version":1,"tracks":[{"id":UUID,"reference":{"bookmark":base64,"lastKnownPath":..., "fileName":...}}]}` (from `PlaylistStore.Body`, `Track`, `TrackReference`; all `Codable`). The type is declared as `com.localplayer.playlist`, conforming to `public.json` and `public.data`, extension `lplaylist` (`Resources/Info.plist`, `PlaylistStore.swift`).

## 2. Per-file portability verdicts

Verdicts: **As is** (compiles on iOS unchanged, as far as imports and calls show), **Changes** (portable after a named edit), **macOS only**. "As is" is a reading verdict, not a compile result. Evidence is the import line and the specific call that decides.

### Playback

| File | Verdict | Evidence |
|---|---|---|
| `Playback/PlaybackEngine.swift` | As is | `Foundation`, `Combine`; protocol plus enums. `PlayResult.noOutputDevice` stays as a case (iOS will not produce it in practice). |
| `Playback/AudioBackend.swift` | As is, with a session hook | `AVFoundation`; `AVAudioPlayer`, `AVAudioPlayerDelegate` exist on iOS. No `AVAudioSession` call anywhere, which iOS requires (section 8). |
| `Playback/AVPlaybackEngine.swift` | Changes | `Foundation`, `Combine`, no AppKit. Depends on `SystemOutputDevices` (CoreAudio) by default and on `VolumeSettingsStore`. Needs: session activation before `start()`, interruption and route handling, no output-device gate. |
| `Playback/OutputDevices.swift` | macOS only | `import CoreAudio`; `AudioObjectGetPropertyData`, `kAudioHardwarePropertyDefaultOutputDevice`. The `OutputDeviceProviding` protocol is portable; `SystemOutputDevices` is not. |
| `Playback/VolumeSettingsStore.swift` | As is | `Foundation`; `UserDefaults`, `CFGetTypeID`/`CFBooleanGetTypeID`. Not used by the iOS UI (section 9). |
| `Playback/VolumeLimits.swift` | As is | `Foundation`; constants only. |

### Playlists

| File | Verdict | Evidence |
|---|---|---|
| `Playlists/PlaylistModel.swift` | As is | `Foundation`; `Track`, `Playlist`, `adding`, `removing`, `moving`. |
| `Playlists/AdvanceDecider.swift` | As is | `Foundation`; defines `RepeatMode`. |
| `Playlists/ShuffleOrder.swift` | As is | `Foundation`; `shuffle(using:)`. |
| `Playlists/PlaybackGate.swift` | As is | `Foundation`. |
| `Playlists/PlayModeStore.swift`, `PlayModeSettings.swift` | As is | `Foundation`, `Combine`; `UserDefaults`, `ObservableObject`. |
| `Playlists/TrackStatusStore.swift` | As is | `Foundation`, `Combine`. Also holds the `PlaylistDocumentEditing` and `TrackResolutionReporting` protocols, which the iOS document must conform to. |
| `Playlists/ReadabilityMarkStore.swift` | As is | `Foundation`, `Combine`. |
| `Playlists/ActiveSessionRegistry.swift` | As is | `Foundation`. |
| `Playlists/PlaylistPlayer.swift` | As is | `Foundation`, `Combine`; talks to `PlaybackEngine`, not AVFoundation. Uses `hasOutputDevice` only through `PlayResult.noOutputDevice`. |
| `Playlists/PlaylistStore.swift` | Changes | `Foundation` only, but `SystemPlaylistFileOperations.replace` uses `NSFileCoordinator` plus `replaceItemAt`, and `save` writes `.lpsave-*` temporaries beside the file. On iOS `UIDocument` owns safe saving. Split a pure `encode(Playlist) -> Data` and `decode(Data) -> LoadResult` out of `save`/`load` (section 5). |
| `Playlists/TrackReference.swift` | Changes | `Foundation`. `bookmarkData(options: [])` and `realpath` compile on iOS as far as I know, but the semantics differ (sections 6 and 14). `canonicalPath` is meaningless for the iOS sandbox. |
| `Playlists/TrackResolver.swift` | Changes | `Foundation`. Uses `.withoutUI` and `.withoutMounting` and a `.Trash` path check. `.withoutMounting` availability on iOS is unverified. The `lastKnownPath` fallback must not run on iOS (stale container paths, section 6). |
| `Playlists/MissingTrackRelinker.swift` | Changes | `Foundation`. Logic is portable. Precondition `FileManager.isReadableFile` on a picked URL needs the scope opened first; the folder-wide match needs a folder grant (section 6). |
| `Playlists/FolderMatcher.swift` | As is, with a scope precondition | `Foundation`; `contentsOfDirectory`. Works only on a URL whose security scope is active. |
| `Playlists/PlaylistDocument.swift` | macOS only | `import AppKit`; subclasses `NSDocument`, uses `NSSavePanel`, `updateChangeCount`, `autosave(withImplicitCancellability:)`, `move(to:)`. The editing logic inside (`replacePlaylist`, undo, `addFiles`, `resolveStatuses`) is portable and should move into a shared model (section 2). |
| `Playlists/PlaylistDocumentController.swift` | macOS only | `import AppKit`; subclasses `NSDocumentController`. |
| `Playlists/PlaylistWindowController.swift` | macOS only | `AppKit`, `UniformTypeIdentifiers`; window controller. |
| `Playlists/PlaylistOpenRouter.swift` | macOS only | `import AppKit`; takes a `PlaylistDocumentController`. |

### Open

| File | Verdict | Evidence |
|---|---|---|
| `Open/FormatClassifier.swift` | Changes (small) | `Foundation`, `UniformTypeIdentifiers`; `resourceValues(.contentTypeKey)`, `FileHandle`. Portable, but it calls `isReadableFile` and sniffs bytes, so it needs the security scope open, and an iCloud placeholder (not downloaded) reads as `fileNotReadable` (section 6). |
| `Open/OpenCoordinator.swift` | As is | `Foundation`; depends on protocols only. |
| `Open/Notice.swift` | As is | `Foundation`; text only. |
| `Open/NoticePresenter.swift` | macOS only | `import AppKit`; `NSAlert`, `NSWindow`. The `NoticePresenting` protocol it conforms to is portable and needs a SwiftUI alert implementation. |

### UI

| File | Verdict | Evidence |
|---|---|---|
| `UI/TransportViewModel.swift` | Changes | `Foundation`, `Combine`; `ObservableObject`, `Timer`. Portable. `volume` and `isMuted` are published and have no iOS use; `Timer` does not tick in the background (fine, section 8). |
| `UI/UIManifest.swift` | As is | `Foundation`; `Bundle.main`, `JSONSerialization`. `WindowKind` has one case, `playlist`, and must grow (section 11). |
| `UI/ManifestChecker.swift` | As is | `Foundation`. |
| `UI/HIGChecklist.swift` | As is | `Foundation`. A Mac HIG checklist parser; the iOS app needs its own checklist file. |
| `UI/TransportControlsView.swift` | macOS only | `import AppKit`; `NSStackView`, `NSButton`, `NSSlider`, `NSTextField`, `NSImage`. |
| `UI/GlassSurface.swift`, `AppearanceModel.swift`, `WindowEnumerator.swift` | macOS only | `import AppKit`. |

### Scripting

| File | Verdict | Evidence |
|---|---|---|
| `Scripting/ActionManifest.swift` | Changes | `import AppKit` is used only by `ParityGate.menuItemsWithoutScriptBinding(in: NSMenu, ...)`, `ExcludedSystemItems` menu titles and `runParityGateCheck` (which builds `AppMenu.makeMenuBar`). `ManifestAction`, `ActionManifest.actions` and `ParityGate.checkParity` are pure value logic. Split the file (section 10). |
| `Scripting/ScriptError.swift` | Changes | `Foundation`. `ScriptFailure` is portable; `extension NSScriptCommand` is macOS only. Move that extension to the Mac target. |
| `Scripting/AppActions.swift` | macOS only (as written) | `import AppKit`; reads `PlaylistDocumentController.current`, `NSApp`. It is the single action layer for scripts and the right shape for intents, but it is wired to `NSDocumentController`. An iOS equivalent must be written against the shared model. |
| `Scripting/ScriptCommands.swift` | macOS only | `import AppKit`; `NSScriptCommand` subclasses, `NSApp.delegate`. |
| `Scripting/AppDelegate+Scripting.swift` | macOS only | `import AppKit`. |

### App and updates

| File | Verdict | Evidence |
|---|---|---|
| `App/AppServices.swift` | Changes | `Foundation`, `AppKit`. AppKit is used for `PlaylistDocumentController` in `connect(controller:)` and `startFromIdle`. The service graph (engine, settings, marks, registry, store, transport) is what an iOS composition root needs; split the AppKit wiring out. |
| `App/LaunchHarness.swift` | As is | `Foundation`; launch-budget verdict maths. Whether iOS wants a launch budget is an open question. |
| `App/LaunchCoordinator.swift`, `AppDelegate.swift`, `main.swift`, `AppMenu.swift`, `CommandLineMode.swift`, `UICheckMode.swift` | macOS only | `import AppKit` in each (`NSApplication`, `NSMenu`, window enumeration). |
| `Updates/UpdateConfiguration.swift` | macOS only (by purpose) | `Foundation`, compiles, but reads Sparkle keys that iOS never has. Do not share. |
| `Updates/UpdaterController.swift`, `SparkleConfigTest.swift` | macOS only | `import Sparkle` (Sparkle is a macOS framework; the package declares only `.macOS`); `SparkleConfigTest` also `AppKit`, `CryptoKit`. |
| `Updates/UpdateMenu.swift` | macOS only | `import AppKit`. |

### Not verified

- I did not compile any file for an iOS destination. "As is" rests on imports and a read of each call.
- I did not read the bodies of `PlaylistWindowController.swift`, `LaunchCoordinator.swift`, `AppDelegate.swift`, `AppMenu.swift`, `CommandLineMode.swift`, `UICheckMode.swift`, `SparkleConfigTest.swift` or `UpdaterController.swift`. Their verdict comes from the import line alone, which is conclusive for AppKit and Sparkle imports.
- `Resources/LocalPlayer.sdef` was read for command and property names only.

## 3. Module and target structure

### Decision

Extract the portable core into a new library target and keep the Mac app as a thin executable on top of it.

```
Package.swift
Sources/
  LocalPlayerCore/      library, macOS + iOS    (Foundation, Combine, AVFoundation, UniformTypeIdentifiers)
  LocalPlayer/          executableTarget, macOS (AppKit, Sparkle, scripting)
Tests/
  LocalPlayerCoreTests/ portable tests, run on macOS and iOS Simulator
  LocalPlayerTests/     Mac-only tests (AppKit, Sparkle, scripts, release)
iOS/
  LocalPlayerIOS.xcodeproj   app target, SwiftUI, App Intents, UIDocument glue
  LocalPlayerIOS/            sources, Info.plist, entitlements, PrivacyInfo.xcprivacy, assets
  LocalPlayerIOSUITests/     XCUITest
```

Package changes: add `.iOS(.v26)` to `platforms`; add `.library(name: "LocalPlayerCore", ...)` product; the Mac target depends on `LocalPlayerCore` and Sparkle. Which iOS deployment target to pick is an open question (section 18); 26 matches the Mac's "current OS only" stance but excludes most of the installed base.

What moves into `LocalPlayerCore`: the "As is" and "Changes" rows above for Playback, Playlists logic, Open logic, `UIManifest`, `ManifestChecker`, `TransportViewModel`, the action list from `ActionManifest`, `ScriptFailure`, `AppServices` without AppKit.

### The cost that is easy to underestimate

Nothing in the app is `public`. Moving types into another module means adding `public` (and public initialisers, since memberwise inits are internal) to every type the Mac or iOS app touches. That is a mechanical but large and review-heavy diff across roughly 40 files, and it changes the Mac app's build in the same commit.

Alternatives rejected:

| Alternative | Why rejected |
|---|---|
| Keep one target, make it multiplatform with `#if os(macOS)` fences | Sparkle and AppKit would sit in the same module; `executableTarget` cannot be linked by an iOS app; `main.swift` and `NSPrincipalClass` assume a Mac process. Fences in 20 files would bury the real boundary. |
| Copy the portable files into the iOS app | Two copies of `AdvanceDecider`, `ShuffleOrder`, `TrackResolver` and the format would drift. The shared on-disk format makes drift a data-compatibility bug. |
| Expose internals with `@testable import` from the app targets | `@testable` needs a debug build with testing enabled; it does not work for a release or App Store archive. |
| Use `package` access level (Swift 5.9+) instead of `public` | Viable and smaller: `package` is visible to other targets in the same package. It does not reach an Xcode app target outside the package. Use `package` for Mac-to-Core and `public` only for what the iOS app target needs. Not verified how this behaves for an Xcode project referencing the package. |

### Building the iOS app

Verified: the repo has no `.xcodeproj` and builds with `swift build` plus `scripts/build-app.sh`, per `docs/tech-architecture.md` and `scripts/`. Verified: SwiftPM alone does not produce a signed iOS `.app` with Info.plist, entitlements, asset catalog and App Store signing. This is general knowledge, not tested here.

Decision: a small hand-maintained Xcode project under `iOS/` that references the repo root as a local package (for `LocalPlayerCore`) and holds the iOS app, its App Intents and its UI tests. The Mac app stays SwiftPM-built and is not moved into Xcode.

Rejected:

- Swift Playgrounds `.iOSApplication` product in `Package.swift`: I believe the `AppleProductTypes` manifest API is unsupported in a tools-6.2 mixed package and gives little control over entitlements and signing. Unverified; do not rely on it.
- Generating the project with XcodeGen or Tuist: reduces merge pain in `project.pbxproj`, adds a tool dependency the owner has not chosen. Raise it as a question (section 18), do not decide it silently.
- Moving the Mac app to the same Xcode project: gains one build system, loses the working `build-app.sh`, notarisation and release tests (`ReleaseScriptTests`, `MinOSConsistencyTests`) that are written against the current scripts.

Known problem: an Xcode project that references the root package will also resolve Sparkle, because the root `Package.swift` declares it. Resolution should succeed (Sparkle is only linked by the Mac target) but this is unverified; if it fails, move the Mac app to its own package (`Mac/Package.swift`) and keep the root package as Core only.

## 4. UI technology and screens

### Decision: SwiftUI, targeting the iOS 26 SDK.

Reasons: the Mac app builds its UI imperatively in AppKit (`TransportControlsView` is an `NSStackView` built in code) so there is no view code to share either way; `TransportViewModel` and `PlayModeSettings` are already `ObservableObject`s with `@Published` state, which SwiftUI observes directly; List, swipe actions, `EditButton`, `.sheet`, `.fileImporter` and `.safeAreaInset` cover the proposal's four screens.

Rejected: UIKit. It gives finer control of the mini player and `UITableView` reordering, but doubles the view code, and the proposal has nothing that SwiftUI cannot express. Revisit only if a spike shows a SwiftUI limitation (known risk: `List` edit-mode move combined with swipe-to-delete and a docked bar; unverified on iOS 26).

Rejected: Mac Catalyst. It would reuse AppKit-era behaviour poorly (the Mac views are AppKit, not UIKit, so nothing is reused) and give a Mac-idiom iPhone app.

### Screens (from the proposal) and their state sources

| Screen | Content | State and actions |
|---|---|---|
| Playlists (home) | Large title, row per playlist with name, track count, playing marker, "1 missing" badge; "+" | Document browser listing (section 5). Counts and missing come from a cheap decode plus `TrackResolver` run, off the main thread, as `PlaylistDocument.resolveStatuses` does today. |
| One playlist | Large title, filled Play and tinted Shuffle buttons, rows; tap plays; swipe removes; Edit reorders; "+" adds files | `PlaylistSession` (shared model, below): `playlist`, `statuses`, `marks`, `player`. |
| Mini player | Playing marker, title, Pause, Next, 2 pt progress | `TransportViewModel`. Shown on screens 1 and 2 through `safeAreaInset(edge: .bottom)`. |
| Now Playing sheet | Title, "Track 2 of 5 · name", seek bar, Play/Previous/Next, Shuffle, Repeat | `TransportViewModel`, `PlayModeSettings`. |

The 2 pt line, 28 pt seek touch height, and 76/56/48 pt sizes come from the proposal and stay there; in code they become named constants, per the project style rule.

### Shared model to extract from `PlaylistDocument`

`PlaylistDocument` mixes NSDocument plumbing with editing logic. Extract the logic into a `PlaylistSession` class in `LocalPlayerCore` that owns `playlist`, `statuses`, `changes`, `addFiles`, `removeTracks`, `moveTrack`, `apply(_:toTrack:)`, `trackResolved`, `resolveStatuses`, and the lazy `player` and `relinker`. It conforms to `PlaylistDocumentEditing` and `TrackResolutionReporting`. The Mac `NSDocument` and the iOS `UIDocument` each hold one and forward `read`/`write`. This is the one real refactor of Mac code, so the Mac tests (`PlaylistDocumentTests`, `MissingFilesTests`, `PlaylistPlayerTests`) are the safety net and must pass before any iOS work builds on it. Undo registration (`undoManager`) stays in the document subclasses because the `NSDocument` and `UIDocument` managers differ; this is a decision, not verified.

## 5. Document model

### Decision: a document-based SwiftUI app with a `UIDocument` subclass for `.lplaylist`, plus the proposal's custom home screen.

The proposal's home is a list of playlists with large title and "+", which is not the system document browser. Two options:

| Option | What it is | Verdict |
|---|---|---|
| A. `DocumentGroup` / `UIDocumentBrowserViewController` as home | System browser UI, Files integration for free | Rejected as the home. It would replace the proposal's playlist rows, playing marker and "n missing" badge. |
| B. Custom home over an app-owned folder, `UIDocument` for open/save, `fileImporter`/`fileExporter` for outside files | Matches mockups | Chosen. Playlists live in the app's Documents folder (visible in Files via `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`) and optionally in the iCloud container. |

Consequence of B: the home must enumerate files itself (`FileManager`/`NSMetadataQuery` for iCloud) and handle rename, delete and duplicate itself, which a document browser would provide. This is more work than A and is the price of the proposal's design. If the owner prefers less work, A with the browser's own rows is the fallback; it breaks the mockup, so it needs an owner decision.

### Type declaration

Reuse the exported UTI exactly: `com.localplayer.playlist`, conforms to `public.json`, extension `lplaylist`, copied from the Mac `Info.plist`. Same identifier on both platforms is what makes a file open in either app. In the iOS `Info.plist`: `UTExportedTypeDeclarations` (same dictionary), `CFBundleDocumentTypes` with `LSItemContentTypes` = that UTI and `LSHandlerRank` Owner, `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`. Whether `UISupportsDocumentBrowser` is set depends on option A or B.

### Reading and writing

`PlaylistStore.load` takes a URL and `save` does temporary-file-then-replace with `NSFileCoordinator`. `UIDocument` already coordinates and safe-saves, and hands the subclass `Data`. So:

- Split `PlaylistStore` into a pure codec: `encode(Playlist) throws -> Data` and `decode(Data) -> LoadResult` (same envelope, same `.corrupt` / `.unsupportedVersion` mapping), and keep `PlaylistStore` as the file-based wrapper built on the codec so the Mac behaviour and tests are unchanged.
- iOS `UIDocument.contents(forType:)` calls `encode`; `load(fromContents:ofType:)` calls `decode`. Autosave is `UIDocument`'s own (`updateChangeCount(.done)` after each edit); the Mac `scheduleAutosave` coalescing is not needed.
- Do not call `PlaylistStore.save` on iOS: its `.lpsave-*` temporaries beside the file would appear in Files and in iCloud sync.
- A failed save must keep the in-memory change and show the existing `Notice.saveFailed` text, as `PlaylistDocument.write` does today. `UIDocument` exposes `handleError(_:userInteractionPermitted:)` for this; mapping is a detail for the spike.

### Sharing the on-disk format with macOS

Format compatibility is a data-model question, not an AppKit one. What is verified: both apps read the same JSON. What breaks:

| Field | Mac writes | iPhone effect |
|---|---|---|
| `bookmark` | Mac bookmark data, not sandboxed, options `[]` | Does not resolve on iPhone: different device, different volume identity. Unverified for iCloud Drive files, where Apple documents some cross-device ubiquitous-item behaviour I have not checked. |
| `lastKnownPath` | Absolute Mac path | Meaningless on iPhone. Must not be used as a fallback there. |
| `fileName` | File name | The only field that survives. Used by `FolderMatcher`. |

Result: a playlist authored on a Mac opens on an iPhone with every track shown as missing, until the person Locates a folder (section 6). The reverse also holds: a bookmark made on iPhone is useless on the Mac and, if `TrackResolver` there falls through to the iPhone's `lastKnownPath`, it will not exist, so the track is missing on the Mac.

This is a product problem, not just a technical one. The honest options:

1. Accept it: playlists are per-device in practice, and the format stays at version 1. Cheapest. Cross-device "just works" is not delivered.
2. Add an optional `relativePath` or a content fingerprint (for example name plus size plus duration) to `TrackReference` as a version 1 compatible optional field, so a folder match can confirm a candidate beyond the name. Old readers ignore unknown keys (`Codable` ignores them; verified by reading `Body`, which uses synthesised decoding), so this does not need `version: 2` and Mac readers keep working. Recommended as a later phase, not in the first one.
3. Bump to `version: 2` to carry per-platform references. Rejected: `PlaylistStore.load` returns `.unsupportedVersion` for any version above 1, so every released Mac build would refuse the file with "made by a newer version". That punishes Mac users for the iPhone app.

Decision for phase 1: option 1, and write `bookmark` and `lastKnownPath` on iOS exactly as the iOS APIs yield, so a Mac reading the file does not crash (the Mac resolver never throws, verified). Check that the Mac `TrackResolver` never treats a stale iPhone path as a valid file: it calls `isPresent`, so a nonexistent path yields `.missing` (verified by reading).

Also note: Mac-written files that an iPhone opens and then saves will overwrite the Mac bookmarks with iPhone bookmarks (`TrackResolver` refreshes references on resolve and `apply` marks the document edited). On iPhone every Mac track resolves as missing, so no refresh occurs for them, and untouched references are preserved. But if the person Locates one track, only that track and the folder matches change. Tracks never relinked keep their Mac bookmark. Verified by reading `MissingTrackRelinker`: only matched ids are applied.

## 6. Track references on iOS and story 005

### What the sandbox changes

An iOS app can read only its own container and URLs the person grants through the document picker, share sheet or Files open-in-place. Access to a granted URL needs `startAccessingSecurityScopedResource()` and a matching stop. That has three consequences for existing code:

1. `TrackReference.make(for:)` must run while the URL's scope is open (it is called right after the picker returns). The bookmark it creates is the persistent grant. On iOS I believe `bookmarkData(options: [])` on a security-scoped picker URL is sufficient and that `.withSecurityScope` is macOS only. Unverified; this is the first spike.
2. Every consumer of a resolved URL must hold the scope while it reads or plays: `FormatClassifier.classify`, `AVAudioPlayer(contentsOf:)`, `FolderMatcher`, `isReadableFile`. Today these take a bare `URL`. Decision: resolution returns a `ScopedURL` handle (URL plus a release closure), and the session holds the handle for the whole time the track is the current or next track. A leak of open scopes is bounded: iOS limits the number of simultaneously open scoped resources (I recall roughly 256; unverified), so the session must close scopes for tracks it is not playing. `TrackStatus.resolved(URL)` then stays unchanged in core and the scope handle lives beside it in the iOS session, so Mac tests do not change.
3. `TrackResolver`: on iOS, skip the `lastKnownPath` fallback and the `canonicalPath` comparison. The container path of the app changes across reinstall and updates, and files outside the container are not reachable by path anyway. Introduce a `ReferencePolicy` injected into `TrackResolver` (Mac: current behaviour; iOS: bookmark only). Corrupt bookmark then yields `.missing`, which keeps the "never throws" contract.

### iCloud files that are not downloaded

Spec 005 lists this explicitly as out of scope for the Mac ("playlists on iCloud Drive that are not downloaded yet", design.md line 401), so no Mac behaviour exists to preserve. On iPhone this is a common case, so it needs a defined state.

New state, iOS only: `TrackStatus` gets no new case in core (adding one would force changes in every Mac `switch`). Instead the iOS session keeps a second dictionary, `availability: [UUID: Availability]` with `.local`, `.downloading(progress)`, `.notDownloaded`. Detection uses `URLResourceValues.ubiquitousItemDownloadingStatus` after resolving the bookmark. Unverified details: whether a bookmark to an evicted file resolves without triggering a download, and whether `isReadableFile` returns false for a placeholder.

Behaviour:

- Tap a not-downloaded track: start the download (`FileManager.startDownloadingUbiquitousItem`), show a progress marker on the row, play when ready. Never mark it unreadable and never call it missing.
- Automatic advance onto a not-downloaded next track: do not stall silently. Skip it exactly like a missing track is skipped (it uses the same hazard-mark path), and start its download. Rationale: consistent with spec 005's "music does not stop". This diverges from "not missing" display and needs the owner's confirmation (section 18).
- Pre-fetch the next track when the current one starts, so the common case is already local.

### Story 005 mapping

| macOS behaviour (spec 005) | iPhone |
|---|---|
| Moved file followed silently, reference refreshed by autosave | Bookmark follows moves inside the same provider. `TrackResolver` already reports `stale`; refresh and `apply` as today. Moves across providers are missing. |
| Deleted or drive not connected: greyed, cannot play | Same status `.missing`. "Drive not connected" becomes "provider not available" (an unmounted file provider extension); I cannot distinguish the two without a spike. |
| Autoplay skips missing, sets hazard mark, no dialog | Unchanged: `PlaylistPlayer` and `PlaybackGate` are portable. Verified by reading that they take only `TrackStatus`. |
| Tap on missing: nothing plays, hazard mark | Tap on a missing row: nothing plays, hazard mark, and a short inline prompt "Locate" (iOS has no context menu on a row by default; swipe action or long press). |
| Locate: pick a file, then folder-match the other missing tracks by name | Picking a file grants one file only. The folder is not readable from it (no parent grant). So the iOS Locate picks a folder (`UIDocumentPickerViewController` with `.folder`), then `FolderMatcher` runs inside the granted folder and relinks every track whose name matches, including the one the person tapped. This replaces "pick a file" with "pick a folder". Single-file Locate stays available as a fallback and relinks only that track. |
| Locate never guesses | Unchanged. Name-only, direct children only, case-insensitive (`FolderMatcher`, verified). |

Open: whether a folder grant gives recursive read of subfolders (it should, but `FolderMatcher` looks only at direct children by spec, so this is moot) and whether a folder bookmark should be stored to relink future missing tracks without asking. Storing it needs a new field in the playlist or a side store; out of scope for phase 1.

## 7. Adding tracks

`fileImporter` with `allowedContentTypes: [.mp3, .wav, .mpeg4Audio]` and `allowsMultipleSelection`. For each URL: open scope, `FormatClassifier.classify` (the same classifier; it already treats extension and byte-sniffing as valid and returns `Notice.unsupported` text), then `adding(_:to:classifier:)` from `PlaylistModel.swift`, then `TrackReference.make`. The `adding` function is portable (verified, `Foundation` only). Music library items (`MPMediaPickerController`) are not files and are out of scope; say so in the product text.

## 8. Playback

### Mapping

| Mac | iPhone |
|---|---|
| `AVPlaybackEngine` | Reused, with a session layer added (below). |
| `AudioBackend` / `AVAudioPlayerHandle` | Reused. `AVAudioPlayer` plays mp3, wav, m4a on iOS. |
| `OutputDeviceProviding` / `SystemOutputDevices` | Replaced by `AlwaysAvailableOutput` (`hasOutputDevice == true`). iOS always has a built-in speaker or receiver route, so the `.noOutputDevice` branch of `PlaylistPlayer` and `OpenCoordinator` is dead on iOS but kept for the Mac. The real failure is "session could not be activated", reported as `.failed`. |
| Output device change on the Mac (no handling today) | Route changes handled by the session layer (below). |

Note that `AVPlaybackEngine.play` calls `backend.makePlayer(for:)` then `newPlayer.start()` and returns `.failed("The audio output could not start playing this file.")` when `start()` is false. With the session inactive on iOS, `play()` can return false, so activation must happen before `start()`.

### Session layer

New in the iOS target (not core): `AudioSessionController`, injected into the iOS composition root and called by a thin `SessionAwareEngine` decorator around `AVPlaybackEngine` (decorator, so Mac `PlaybackEngineTests` are untouched).

- Category: `.playback`, mode `.default`. Spoken-word and music both fit; `.spokenAudio` mode is for podcasts and is not chosen. No mixing options: this is the foreground audio app that should interrupt others and show in Now Playing.
- Activate in `play` and `resume`, deactivate (with `.notifyOthersOnDeactivation`) when playback goes idle or after a pause grace period. A pause must not deactivate, or lock screen controls disappear.
- Interruptions: observe `AVAudioSession.interruptionNotification`. On `.began`, set paused state through the engine (`pause()` semantics, so position is kept and `PlaylistPlayer` sees no `.finished`). On `.ended` with `.shouldResume`, call `resume()`. Without `.shouldResume`, stay paused. `AVAudioPlayerDelegate` interruption callbacks are deprecated, so notifications are used; I believe this is correct but did not check the current SDK.
- Route changes: observe `routeChangeNotification`. `.oldDeviceUnavailable` (headphones or Bluetooth lost): pause. Other reasons: ignore.
- Background: `UIBackgroundModes` = `audio` in the iOS `Info.plist`.
- Session and engine events stay on the main thread, matching the engine's documented "all calls on the main thread" rule.

### Now Playing and remote commands

New `NowPlayingBridge` in the iOS target, subscribing to `TransportViewModel` and `engine.events`.

- `MPNowPlayingInfoCenter.default().nowPlayingInfo`: title (`engine.currentURL?.lastPathComponent`, as the Mac shows it, not tag metadata; reading ID3 or m4a tags is a possible improvement, not designed here), playlist name as album title, `MPMediaItemPropertyPlaybackDuration`, `MPNowPlayingInfoPropertyElapsedPlaybackTime`, `MPNowPlayingInfoPropertyPlaybackRate` 1.0 or 0.0, queue index and count.
- Update on state change, seek and track change only, not every 250 ms: the system extrapolates from elapsed time and rate. This also respects the Mac's rule of no work in a render path. `TransportViewModel`'s `Timer` is not needed for the lock screen.
- `MPRemoteCommandCenter`: enable `play`, `pause`, `togglePlayPause`, `nextTrack`, `previousTrack`, `changePlaybackPosition`; set `stopCommand` disabled (no Stop on iOS). Disable `nextTrack` and `previousTrack` when no playlist session is active, mirroring `skipControlsAvailable`. Handlers call the same `TransportViewModel` methods as the buttons.
- Remote command targets are added once and removed on teardown to avoid duplicates.
- Previous semantics: check what `PlaylistPlayer.previous()` does before wiring lock screen Previous, because lock screens users expect "restart if more than a few seconds in". Not checked in this session; it affects only the label, not the structure.

### Single-file playback and Stop

`OpenCoordinator.open(url)` plays a single file outside any playlist. The proposal has no single-file screen. Opening an audio file from Files ("Open in LocalPlayer") can reuse it and show the mini player only. Decision: support it in phase 3, not phase 1.

No Stop: the proposal says swipe-dismiss the mini player. Mapping: dismissing calls the existing `engine.stop()`, which sends `.stopped` and ends the playlist session through `PlaylistPlayer` (verified in the `handle(_ event:)` switch). The mini player is not hidden on pause. Lock screen has no Stop either.

### Moving from one track to the next

Background audio on iOS is a standard capability, not a risk in itself: with `UIBackgroundModes` = `audio` and an active `.playback` session, the app keeps running while it plays and a playlist carries on with the screen locked. That is how every music and podcast app works. This part rests on my knowledge of the platform, not on a test in this repo, so spike (b) in section 16 confirms it on a device.

What does need a decision is the hand-off between tracks. Today `AVAudioPlayerHandle.onFinish` fires from `audioPlayerDidFinishPlaying`, then `AVPlaybackEngine.trackFinished` sends `.finished`, then `PlaylistPlayer` creates the next `AVAudioPlayer` and starts it. That leaves a short silent gap (a main-thread hop plus `prepareToPlay`). On the Mac nobody minds. On iPhone the gap is audible, and starting a new player only after audio has stopped is the least robust way to keep a session going.

Decision: make the iOS engine preload the next track. When a track starts, the playlist asks the decider what follows (the decider is a pure function and already answers this), builds that `AVAudioPlayer`, calls `prepareToPlay()`, and starts it at the current player's `deviceCurrentTime + duration` with `play(atTime:)`. This needs a new "prepare next" operation on `AudioPlayerHandle` and the engine, which the Mac backend can leave unimplemented, so the Mac behaviour and tests do not change. Three cases need handling: the next track turns out to be unreadable (fall back to the normal skip path), the person presses Next or seeks (discard the preloaded player), and shuffle or repeat changes mid-track (re-ask the decider). An `AVQueuePlayer` or `AVAudioEngine` would also work, but each replaces the single-player engine, so they are the fallback, not the first choice.

## 9. Volume and mute

The Mac spec (story 011: `prd.ctrl.volume_scope`, `prd.ctrl.volume_persist`) wants an in-app level separate from system volume, persisted. On iOS the hardware buttons and Control Center own the level; a second in-app slider multiplies it and is confusing. The proposal already drops it.

Decision:

- No in-app volume or mute UI.
- The iOS composition root injects a `VolumeSettingsStoring` stub returning `(volumeDefault, muteDefault)` and ignoring saves, so `AVPlaybackEngine`'s `effectiveGain` is always 1.0 and nothing is persisted. This needs no engine change and keeps `PlaybackEngineTests` valid. `VolumeSettingsStore` and `UserDefaults` keys are not touched.
- `TransportViewModel.volume` and `isMuted` remain published but unused.
- Reading system volume for scripts (`volume` property): expose read-only `AVAudioSession.outputVolume` through the intents layer if a Shortcuts action wants it; do not offer a setter, because iOS provides no public API to set system volume.

Rejected:

- `MPVolumeView` in the Now Playing sheet: it is the system control, so it would not conflict with the system level, and many players include it. It adds a control the proposal removed deliberately. Offer as an owner choice.
- Keeping an in-app gain: re-creates the two-volumes confusion on a platform without a Mac-style per-app mixer.

Divergence from spec 011 and `playback.volume.*` is intentional and listed in section 13.

## 10. Automation parity: App Intents

### The existing contract (verified)

`ActionManifest.actions` lists 19 actions, each with `uiBinding` and `scriptBinding`. `ParityGate.checkParity` compares them with the names it parses from `LocalPlayer.sdef` (commands and read-write application properties) and fails on any action without a script entry or any script entry without an action. `runParityGateCheck` also fails on any app menu item that is neither an action nor an excluded system item. Scripts and UI converge on `AppActions` and the same view model methods ("a click and its script cannot drift apart").

### iOS counterpart

Add a third binding to `ManifestAction`: `intentBinding: String?`, and a `platforms: Set<Platform>` (macOS, iOS) so an action can be absent by design. App Intents are the iOS script surface.

| Action id | Mac script | iPhone App Intent | iPhone status |
|---|---|---|---|
| openFile | open audio file | `OpenAudioFileIntent` (takes `IntentFile`) | Phase 3 (single file, section 8) |
| play | play | `PlayIntent` | Phase 2 |
| playTrack | play track | `PlayTrackIntent` (playlist entity + position) | Phase 2 |
| pause | pause | `PauseIntent` | Phase 2 |
| stop | stop | none | **Not on iOS by design** (platforms: macOS only) |
| seek | seek | `SeekIntent` (seconds) | Phase 2 |
| next | next track | `NextTrackIntent` | Phase 2 |
| previous | previous track | `PreviousTrackIntent` | Phase 2 |
| volume | volume | none | **Not on iOS by design** (system volume) |
| mute | muted | none | **Not on iOS by design** |
| shuffle | shuffle | `SetShuffleIntent` (Bool) | Phase 2 |
| repeat | repeat mode | `SetRepeatIntent` (off/all/one, enum from `RepeatMode`) | Phase 2 |
| newPlaylist | new playlist | `NewPlaylistIntent` (name) | Phase 2 |
| renamePlaylist | rename playlist | `RenamePlaylistIntent` | Phase 2 |
| addTrack | add track | `AddTrackIntent` (`IntentFile`, playlist) | Phase 2 |
| removeTrack | remove track | `RemoveTrackIntent` | Phase 2 |
| reorderTrack | move track | `MoveTrackIntent` | Phase 2 |
| locate | locate track | `LocateTrackIntent` | Needs UI: a folder grant cannot be given from a background intent. The intent should open the app to the Locate picker (`openAppWhenRun`). Say so rather than pretend parity. |
| checkForUpdates | check for updates | none | **Not on iOS** (App Store) |

Properties that scripts read (`playing`, `current track`, `position`, `muted`, `volume`, `shuffle`, `repeat mode`; playlist `name`, `track count`, `file`) map to `AppEntity` and `AppEnum` queries or return values of intents. An `AppEntity` for a playlist (id, name, track count, missing count) is needed for the parameters above. Intents run in a different context from the app UI; an intent that controls playback must reach the same engine as the foreground app, so either set `openAppWhenRun` or run in-process via an `AudioPlaybackIntent` (iOS 18 API, I believe; unverified for details). Decision: use `AudioPlaybackIntent` for Play, Pause, Next, Previous, Seek so they work from Siri and the Action button without launching the UI; if the spike shows it cannot reach the live engine, fall back to `openAppWhenRun`.

Error mapping: reuse `ScriptFailure` numbers and messages as the `localizedDescription` of an intent error, so one set of refusal strings serves both. Verified that `ScriptFailure` is Foundation-only once its `NSScriptCommand` extension is moved.

### The iOS action layer

`AppActions` is the right shape (validate, map to numbered refusal, call the same handler as the UI) but reads `PlaylistDocumentController.current`. Introduce `ActionHost` in core that provides the three things `AppActions` needs: the list of open sessions, the transport, and the engine. Mac `AppActions` adapts `PlaylistDocumentController`; iOS adapts the session registry. Intents call the iOS adapter. This is a design intent, not something I checked line by line (I read the first 40 lines of `AppActions`).

### Parity gate on iOS

Two checks, both required in CI:

1. Manifest-level (pure Swift, runs on macOS in `LocalPlayerCoreTests`): for every action whose `platforms` includes iOS, `intentBinding` is non-nil; for every action not on iOS, a reason string exists; every intent in the `IntentCatalog` (a hand-maintained array of intent type names, one per action) corresponds to an action. This is the existing `checkParity` shape with a different source of names.
2. Binary-level (iOS target test): verify the catalog against the real types by referencing each intent type in the test (a compile error when an intent is missing) and instantiating it with default parameters. A stronger check would parse the App Intents metadata the build emits (`Metadata.appintents`), but I do not know its format or location in the product, so it is not designed. Unverified.

The gate counts only app-specific UI. The system-document menu exclusions in `ExcludedSystemItems` have no iOS analogue; iOS has no menu bar, so check 2 for "menu item with no equivalent" becomes "every control in the UI manifest (section 11) with a job must map to an action". That connects the two gates: `ui-manifest-ios.json` elements reference an action id, and the test fails when an element has no action or an action has no element on any platform where it should appear.

Tests for both routes, as the project rule requires: each intent has a test through the intent's `perform()` and a test through the corresponding XCUITest tap, asserting the same final state through the same view model, as `DualPathTests` does on the Mac (I saw it imports AppKit and XCTest; I did not read its structure).

Constraint to check: Shortcuts and Siri phrases are limited to a small number of `AppShortcut`s per app (I recall 10; unverified). 15 intents exist, so some must be visible in Shortcuts only, not as suggested phrases.

## 11. UI manifest and element-to-job check (spec 007)

### Mac today (verified)

`Resources/ui-manifest.json` lists 16 elements for the `playlist` window, each with a job (`play_file`, `play_playlist`, `manage_playlists`). `UIManifest` loads it; `ManifestChecker.check` compares recorded elements with those observed in each `WindowState` (idle, playing, editing_playlist, notice_shown, untitled_empty) and reports `unrecorded`, `unidentified` (no accessibility identifier) and `stale` elements. `UICheckMode` and `WindowEnumerator` (AppKit) collect what is visible.

### iOS

`UIManifest` and `ManifestChecker` are Foundation-only and move to core unchanged except that `WindowKind` and `WindowState` grow:

- `WindowKind`: `playlists`, `playlist`, `miniPlayer`, `nowPlaying` (screens, not windows; keep the Swift name or rename in the same change as a migration).
- `WindowState`: add `missingTracks`, `notDownloaded`, `emptyPlaylists`; `editing_playlist` maps to the proposal's Edit mode.
- A new file `Resources/ui-manifest-ios.json`; the macOS file is untouched. Reusing element ids where the control is the same (`playback.playpause`, `playback.next`, `playback.previous`, `playlist.shuffle`, `playlist.repeat`, `playback.position`, `playback.nowplaying`, `playlist.add`, `playlist.remove`, `playlist.tracks`) keeps one vocabulary; removed: `playback.stop`, `playback.mute`, `playback.volume`. `playback.elapsed` and `playback.remaining` stay on Now Playing. New: `miniplayer.bar`, `miniplayer.progress`, `playlists.list`, `playlists.add`, `playlist.playbutton`, `playlist.shufflebutton`, `playlist.locate`.
- SwiftUI sets identifiers with `.accessibilityIdentifier(...)`. The same value feeds the XCUITest query, so the id in the manifest, the id in the view and the id in the test are one constant, defined once in core.
- Observation: XCUITest runs out of process, so there is no in-app `WindowEnumerator`. Replace it with a UI test that walks the accessibility tree (`app.descendants(matching: .any)`), builds `[ObservedElement]` for each state and calls `ManifestChecker.check` (core, linked into the UI test target). The "unidentified" check needs elements with an interaction role (button, slider, cell, switch). Mapping XCUITest `elementType` to the manifest's `role` string is a detail; I did not read `WindowEnumerator` bodies to see what `role` strings the Mac produces.
- "Only what I need on screen" (spec 007) applies: the check fails on anything visible that is not in the manifest, so a stray control is caught the same way as on the Mac.

States have to be reachable by launch argument or fixtures (a playlist with a missing track, an empty app, a not-downloaded file) because UI tests cannot create an evicted iCloud file in the simulator (section 12).

## 12. Testing strategy

### What carries over

Candidates for `LocalPlayerCoreTests`, chosen by imports (XCTest and `@testable import LocalPlayer` only, no AppKit): `AdvanceDeciderTests`, `PlayModeTests`, `PlaylistDataTests`, `PlaybackEngineTests` (uses Combine), `PlaylistPlayerTests`, `OpenTests`, `MissingFilesTests`, `HIGChecklistTests`, `LaunchHarnessTests`, `LaunchCoordinatorTests` (imports are clean but it exercises a type in an AppKit file, so likely Mac only), `E2ETests`, parts of `UIManifestTests` and `ScriptingTests` (the manifest and parity logic).

Not verified: I did not read the test bodies, so which of these actually run on iOS is unknown. Specific traps seen in the code I did read:

- `Fixtures.directory` is derived from `#filePath`, which on a simulator points into the Mac's source tree; the simulator can read host paths but a device cannot, and a cleaner approach is to bundle fixtures as resources (`resources: [.copy("Fixtures")]`). Fixture mp3/wav/m4a files exist in `Tests/Fixtures`.
- `TempDir` uses `FileManager.default.temporaryDirectory` and `realpath`; fine.
- `MissingFilesTests` references `Process` once; the spec says it uses real disk images created with `hdiutil`. `Process` and `hdiutil` do not exist on iOS, so the "drive not connected" integration cases stay Mac-only.
- `MinOSConsistencyTests`, `ReleaseScriptTests`, `UpdateConfigurationTests`, `UpdaterControllerTests`, `SparkleSelfTestTests` and the AppKit tests (`NativeLookTests`, `DualPathTests`, `TransportTests`, `PlaylistDocumentTests`, `PlaylistOpenRouterTests`, `LaunchDocumentTests`, `ReviewFixTests`, `UsabilityFixTests`) stay in the Mac test target.

Decision: run the shared target on both `swift test` (macOS) and `xcodebuild test -destination 'platform=iOS Simulator,...'`. Running on both is what makes the shared core a real contract.

### New iOS tests

| Layer | What | Tool |
|---|---|---|
| Unit | `UIDocument` read/write round trip against the codec, including `.corrupt` and `.unsupportedVersion(2)`; Mac-written fixture file loads | XCTest on simulator |
| Unit | Session layer with a fake `AVAudioSession` wrapper: interruption began/ended, route change, activation failure returns `.failed` | XCTest, injected protocol |
| Unit | `NowPlayingBridge` against a fake info center and command center: elapsed, rate, enabled commands, no Stop | XCTest |
| Unit | Reference policy: iOS resolver ignores `lastKnownPath` | XCTest |
| Unit | Intent parity gate, section 10 | XCTest |
| UI | Screens 1 to 4, Locate through a folder, add via `fileImporter` (the system picker is out of process and hard to drive; use a test-only injection of picked URLs), Dynamic Type, manifest check | XCUITest |
| Both routes | Each action through UI and through its intent, same final state | XCUITest + XCTest |

### Simulator limits

Cannot or should not be asserted in the simulator, from general knowledge of the simulator (unverified here):

- Real audio output, Bluetooth routes, headphone unplug, and real interruptions (phone call, alarm). The simulator can fake some, not reliably.
- Lock screen and Control Center rendering of Now Playing, remote commands from AirPods or CarPlay.
- Background audio and the preloaded hand-off between tracks (section 8). Needs a device.
- iCloud Drive eviction and download. The simulator's iCloud behaviour differs; a not-downloaded file cannot be produced faithfully.
- Security-scoped bookmark behaviour for files from other providers (the picker UI reaches only the simulator's own Files).
- Performance of startup and scrolling on real hardware.

Each needs a manual device checklist recorded in `docs/` (the Mac has `docs/hig-checklist.md` checked by `HIGChecklist.swift`; create an iOS equivalent file and reuse the same validator, which is already portable).

## 13. Divergences from macOS specs

| Spec | Mac | iPhone | Reason |
|---|---|---|---|
| 011 `prd.ctrl.stop` | Stop button returns to start | No Stop; pause plus swipe-dismiss mini player | Platform convention, per the UX proposal |
| 011 `volume_scope`, `volume_persist` | In-app level separate from system, persisted | No in-app level; system volume only | Hardware buttons and Control Center own it |
| 011 `mute` | In-app mute | None | Same |
| 009 AppleScript parity | AppleScript | App Intents, with listed absent actions (stop, volume, mute, check for updates) | No AppleScript on iOS |
| 010 updates | Sparkle | App Store / TestFlight | Sparkle is macOS only |
| 005 Locate | Pick a file, folder match | Pick a folder, folder match | Sandbox grants only picked items |
| 005 not downloaded | Out of scope | New availability state | iCloud placeholders are normal on iOS |
| 003 Finder open | `NSDocument` + Launch Services | Files "Open in" | Platform |
| 002 double-click plays | Double-click | Tap | No double-click on iOS |
| 007 manifest | One window kind | Four screen kinds, separate manifest file | Different layout |
| Mac spec "window close stops playback" | Closing playlist window stops its session | Navigating back from a playlist does not stop playback | A mini player exists to keep music playing |

The last row is a real behaviour decision. The Mac rule (commit `3d0d9b5`, "window close stops playback") stops playback when the playlist window closes. On iPhone, popping back to the playlists list must not stop playback, or the mini player has no purpose. Playback ends by explicit dismiss, by the end of the session, or by playing something else (`ActiveSessionRegistry.begin` already ends the previous session, verified).

## 14. Updates, signing, entitlements, privacy

- Distribution: TestFlight for beta, App Store for release. No Sparkle, no appcast, no `scripts/release.sh` for iOS. `UpdateConfiguration`, `UpdaterController` and `SparkleConfigTest` are not compiled into the iOS target (they live in the Mac target).
- Signing: Apple Developer Program team, automatic signing in the Xcode project, bundle identifier distinct from the Mac `com.localplayer.app` unless a universal purchase is wanted (open question). Whether an iOS app and the existing Developer ID Mac app can share a bundle id for Universal Purchase is an App Store Connect matter I did not check; the Mac app is not distributed through the Mac App Store today (`docs/tech-architecture.md`: Developer ID, notarised, DMG), so universal purchase does not apply.
- App Sandbox is mandatory on iOS (implicit). Entitlements: none required for a first release other than the iCloud container if section 5's iCloud option is taken (`com.apple.developer.icloud-container-identifiers`, `com.apple.developer.ubiquity-container-identifiers`). The Mac's `network.client` is not needed: nothing in the app uses the network apart from Sparkle (verified by the entitlements file and imports).
- `Info.plist`: `UIBackgroundModes` = `audio`; `UIFileSharingEnabled`; `LSSupportsOpeningDocumentsInPlace`; `UTExportedTypeDeclarations` and `CFBundleDocumentTypes` as section 5; `UILaunchScreen`; `NSUbiquitousContainers` only if iCloud container is used. No usage-description strings are needed: the app uses no camera, microphone, photos, location or contacts. `NSAppleMusicUsageDescription` only if the Music library is added later.
- Privacy manifest (`PrivacyInfo.xcprivacy`): the app reads and writes `UserDefaults` (`PlayModeStore`, `VolumeSettingsStore`), which is a required-reason API category (`NSPrivacyAccessedAPICategoryUserDefaults`). It reads file metadata (`resourceValues`, file timestamps via `contentTypeKey`; it does not read creation or modification dates in code I saw), which may fall under the file timestamp category. Verify with Xcode's privacy report on an archive; I did not enumerate the reasons. No tracking, no data collected, no third-party SDKs.
- App Store privacy label: "Data not collected" is accurate on what I read (no network use, no analytics); re-verify before submission.
- Release gates to port from the Mac: `MinOSConsistencyTests` (plist, package and script must agree on the minimum OS) needs an iOS version covering `IPHONEOS_DEPLOYMENT_TARGET`, the Package `.iOS(...)` and the Xcode project.

## 15. Accessibility and iPad

### Accessibility (from the proposal, with how each is built)

- Dynamic Type: system text styles (`.largeTitle`, `.body`, `.caption`) only, no fixed point sizes for text. Controls are `Image`/`Button` with minimum frame constants of 44 pt; the Now Playing layout switches to a vertical stack at accessibility sizes (`dynamicTypeSize.isAccessibilitySize`) and a unit test or XCUITest at `accessibilityXXXL` checks that Play, Previous, Next and the seek bar remain hittable.
- VoiceOver: the seek bar is an `accessibilityAdjustableAction` element with a label and value ("1 minute 12 of 3 minutes", built with `DateComponentsFormatter` or `Duration.formatted`, not string concatenation); the playing row has `accessibilityValue` "playing"; missing rows read "missing, Locate available" as a custom action; mini player has a single combined element with Pause and Next as custom actions.
- Reduce Motion: no spring or slide animation on sheet, marker or progress when `accessibilityReduceMotion` is on. The proposal's haptic tick on Shuffle and Repeat uses `UIImpactFeedbackGenerator` and does not depend on Reduce Motion, but should respect a system haptics setting.
- Contrast and Increase Contrast: follow system colours, no custom palette. The Mac `HIGChecklist` items do not transfer; write an iOS list of the same format.
- Not verified: any behaviour on a device or simulator.

### iPad

Follow-up, not in this plan's phases. The proposal says to reuse the Mac layout (sidebar of playlists, list, control block on top). With SwiftUI this is `NavigationSplitView` over the same sessions, so the data layer needs no change. Decision now: keep `TARGETED_DEVICE_FAMILY` iPhone only for the first release; do not build iPhone-only assumptions into the core (no global singleton for the "current playlist" the way `PlaylistDocumentController.current` is global today).

## 16. Phased delivery plan

No durations are estimated. Each phase ends only when its exit criteria pass.

| Phase | Scope | Exit criteria |
|---|---|---|
| 0. Spikes | On a real device: (a) picker URL to `bookmarkData(options: [])` to relaunch to resolve; (b) a preloaded next-track hand-off (`play(atTime:)`) across a track boundary with the screen locked, confirming playback carries on and measuring the gap; (c) `AudioPlaybackIntent` reaching the live engine; (d) iCloud evicted file behaviour; (e) Xcode project resolving the root package with Sparkle | Each of the five has a written result with the exact API behaviour, or the design item that depends on it is revised. No production code merged from this phase. |
| 1. Core extraction | `LocalPlayerCore` target; `public`/`package` access; `PlaylistSession` extraction; `PlaylistStore` codec split; `ActionManifest` split; `ScriptFailure` split; Mac app and tests re-pointed | All existing Mac tests pass unchanged in behaviour (suite count and names the same); `swift build` for the Mac app works; Mac scripts and release flow untouched; shared tests also pass on iOS Simulator. |
| 2. iPhone app, playback and lists | iOS project; SwiftUI screens 1 to 4; `UIDocument`; fileImporter add; session layer; background audio; Now Playing and remote commands; no Stop, no volume | Manual device checklist passes (interruptions, unplug, lock screen, background, track gap); `ui-manifest-ios.json` check passes in XCUITest; accessibility checks pass at the largest Dynamic Type; a Mac-written `.lplaylist` opens and shows tracks missing without crashing; an iPhone-written file opens on the Mac with tracks missing and no crash. |
| 3. Missing, Locate, iCloud | Reference policy; folder Locate; availability state; pre-fetch; Files "Open in" for single file | Story 005 cases that apply (TC set for missing, locate, autoskip) pass on iOS with the folder variant; a not-downloaded track never plays silently and never shows as missing; device checklist for iCloud. |
| 4. Intents | `ActionHost`, intents, parity gate, both-route tests | Gate passes in CI; every iOS-applicable action has a test through UI and through intent; absent actions have a recorded reason. |
| 5. Ship | Privacy manifest, App Store listing, TestFlight | Archive validates; privacy report reviewed; TestFlight build installed on a device by someone other than the author. |
| Later | iPad; relative-path or fingerprint field; Music library; tag metadata | Owner decision. |

Order rationale: spikes first because the largest unknowns (bookmarks, intent reach) can each invalidate a later phase, and the hand-off spike sets how the engine seam is changed. The intents phase is after the UI because they call the same handlers; but the parity gate's manifest-level check (section 10, check 1) should run from phase 2 so a UI action never ships without a recorded intent status.

## 17. Risks, ranked

Background playback is not listed: it is a standard capability (section 8). The track hand-off is a design task with a known approach, and spike (b) confirms it on a device.

1. **Cross-device playlists do not resolve.** The shared format carries bookmarks that are device-local, so the "same `.lplaylist` on both" idea in the proposal delivers a playlist whose tracks are all missing on the other device. The user-visible result may be read as a bug. Mitigation: product copy, the fingerprint field (later), or deciding that playlists are per-device. Needs owner decision.
2. **Security-scope and iCloud behaviour is unverified.** The reference design (`TrackReference`, `TrackResolver`, `FolderMatcher`, `FormatClassifier`) assumes a readable URL. On iOS each needs an open scope and a downloaded file. Errors here show up as intermittent "unreadable" or "missing" tracks, which erode trust in story 005's core value.
3. **Core extraction churn.** No `public` anywhere; a wide mechanical diff touches the working Mac app and its large test suite in one go. Mitigation: do it as phase 1 alone, behind the full Mac suite, with no iOS code in the same change.
4. **Parity gate on iOS is weaker than the Mac one.** The Mac gate parses a real artefact (the sdef). The iOS gate checks a hand-kept catalog and compiled types; it cannot prove the system sees the intents. A broken `AppShortcut` or metadata issue would pass CI.
5. **SwiftUI list edit mode with swipe actions and a docked bar.** Known to be fragile historically; unverified on iOS 26. Fallback is a `UIViewControllerRepresentable` table.
6. **Xcode project in a SwiftPM-only repo.** Adds merge-conflict-prone `project.pbxproj` and a second build system for the owner to maintain. Mitigation: keep the project minimal, all logic in packages.
7. **Deployment target choice.** iOS 26 only shrinks the audience; a lower target needs a check of every API and glass styling used.

## 18. Open questions for the owner

1. Should a `.lplaylist` made on one device be expected to work on the other? If yes, do you accept adding an optional fingerprint or relative-path field to `TrackReference` (version 1 compatible), or should playlists be per-device?
2. Is the proposal's custom Playlists home a hard requirement, or is the system document browser acceptable to save work (section 5, options A and B)?
3. Do you want iCloud Drive as a storage location for playlists in the first release? It adds a container entitlement and the not-downloaded state.
4. A not-downloaded next track during autoplay: skip it like a missing track, wait for the download, or stop?
5. iOS deployment target: 26 only, matching the Mac, or lower?
6. Xcode project: hand-maintained, or generated (XcodeGen/Tuist)? Is a second build system acceptable?
7. Single audio files opened from Files: in scope for the first release, or later?
8. Keep an `MPVolumeView` in Now Playing, or no volume control at all?
9. Should navigating out of a playing playlist keep it playing (my recommendation, section 13) or follow the Mac rule and stop?
10. Is the Mac "Stop" absence on iPhone final, given spec 011 and `prd.ctrl.stop`? Should the Mac specs be amended to say the requirement is macOS-scoped, so the two sets of specs agree?
11. Bundle identifier and team for the iPhone app, and whether the App Store is the only target (no ad hoc distribution).
