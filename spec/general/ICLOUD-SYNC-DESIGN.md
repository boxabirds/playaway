# iCloud sync: design

Status: proposal. Nothing here was built, compiled or run. Written 2026-10-06 against the `main` checkout. This is a separate feature from the iPhone app (`IPHONE-TECH-DESIGN.md`). It is the only bridge between Mac and iPhone: without it, a playlist made on one device is not expected to work on the other.

## 0. How to read this

- "Verified" means I read the file in this repo. It does not mean I built or ran anything.
- "Unverified" means it rests on my knowledge of Apple platform APIs, with no header, sample or device check in this session. Each unverified item names what would verify it. The ones that can sink the design are the phase 0 spikes in section 11 (S1 to S6).
- No durations and no sizes are estimated. Where a limit is needed (lookahead count, timeouts) it is a named constant whose value is chosen from a spike result, not guessed here.
- Where this design needs a spec to change, the change is listed in section 12 and nothing under `spec/stories/` is edited by this document.

## 1. Product statement and the default

Playaway can keep chosen playlists and the audio they use in iCloud Drive, so they play on the person's other devices. It is opt-in, offered by invitation, and turned on per device.

**When sync is off, which is the default, nothing changes from today.** Specifically, and testable:

- No iCloud API is called. No container is requested, no metadata query runs, no file is copied.
- `.lplaylist` files are written byte for byte as today (`version: 1`, the three `TrackReference` keys). A golden-file test pins this (section 10).
- Save panel, Open panel, menus other than one added item, window contents and scripting behave as now.
- The one visible difference is one extra File menu item, "iCloud Sync…" (section 3), and, once, a possible invitation (section 3.2).
- A Mac with the app bundled ad hoc (no iCloud entitlement) behaves exactly like a sync-off Mac and shows that item disabled.

## 2. What the code does today (verified)

| Fact | Source |
|---|---|
| A track is `{id: UUID, reference: TrackReference}`. A playlist is its tracks in order. Its name is its file name, not stored inside. | `Playlists/PlaylistModel.swift` |
| `TrackReference` is `{bookmark: Data, lastKnownPath: String, fileName: String}`, all non-optional, synthesised `Codable`. The bookmark is made with `options: []`. The stored path is the `realpath`. | `Playlists/TrackReference.swift` |
| `TrackResolver.resolve` tries the bookmark, then `lastKnownPath`, else `.missing`. It never throws. A path under `.Trash` counts as missing. It returns a refreshed reference whenever the bookmark is stale or the path changed. `isPresent` is `FileManager.fileExists` and not a directory. | `Playlists/TrackResolver.swift` |
| `TrackStatus` has two cases, `.resolved(URL)` and `.missing`. `PlaybackGate` switches over exactly those two. | `TrackResolver.swift`, `PlaybackGate.swift`, `TrackStatusStore.swift` |
| `FolderMatcher` lists the direct children of one folder and matches by lower-cased file name only. `MissingTrackRelinker` runs it on the folder of the file the person located. | `FolderMatcher.swift`, `MissingTrackRelinker.swift` |
| The file is UTF-8 JSON, `{"version":1,"tracks":[...]}`, written with `.prettyPrinted, .sortedKeys`. `load` returns `.unsupportedVersion` for any version above 1. | `PlaylistStore.swift` |
| `save` writes a `.lpsave-<name>-<uuid>` temporary beside the destination, then `NSFileCoordinator` `.forReplacing` plus `replaceItemAt`. It deletes stray temporaries beside the file on the next save. | `PlaylistStore.swift` |
| `PlaylistDocument` is an `NSDocument` with `autosavesInPlace == true`. Every edit calls `updateChangeCount(.changeDone)` and a main-queue coalesced `autosave`. `read(from:)` and `write(to:)` call the store. A failed write shows `Notice.saveFailed` and keeps the change in memory. | `PlaylistDocument.swift` |
| On open, `resolveStatuses` resolves every track off the main thread and calls `apply(reference)` for each result. `apply` is a no-op when the reference is equal, so an unchanged reference causes no write. | `PlaylistDocument.swift` |
| `PlaylistPlayer.prepare` resolves, gates, then classifies. A file the classifier calls unsupported (including `fileNotReadable`) is refused, marked with the session hazard mark, and skipped by `playLoop`. So today an evicted iCloud file that exists as an unreadable stub would be skipped and hazard-marked, not downloaded. Whether that case occurs is unverified (S2). | `PlaylistPlayer.swift` |
| The Mac app is not sandboxed. `build-app.sh` aborts if `com.apple.security.app-sandbox` is present in the entitlements file ("Sparkle replaces the app in place"). `LocalPlayer.entitlements` holds only `com.apple.security.network.client`. The release bundle is hand-assembled, signed inside-out with hardened runtime and a Developer ID identity, notarised, stapled. `build-app.sh` copies no provisioning profile. | `Resources/LocalPlayer.entitlements`, `scripts/build-app.sh` |
| `bundle-dev.sh` signs the dev bundle with `codesign --force --deep --sign -` and no entitlements. | `scripts/bundle-dev.sh` |
| `Info.plist` has no `NSUbiquitousContainers` key. The bundle id is `com.localplayer.app`. `Package.swift` is macOS 26 only. | `Resources/Info.plist`, `Package.swift` |
| There is no Settings or Preferences menu item, no Settings window, and no list of playlists. | `App/AppMenu.swift` (grep), spec 004 "Does not show a list of all playlists" |
| Opening needs only a URL: `store.load` is called in one place, `PlaylistDocument.read`. | grep over `Sources/` |
| The UI manifest has one window kind (`playlist`) and a closed set of three jobs: "a fourth needs a code change and a PRD change". Row decorations (playing marker, hazard) are not manifest elements. | `UI/UIManifest.swift`, `Resources/ui-manifest.json` |
| Scripting: 19 actions in `ActionManifest`. `ParityGate` compares them with the sdef's commands and read-write application properties. Errors are numbered, 1001 to 1008, "may change until the first release". | `Scripting/ActionManifest.swift`, `ScriptError.swift` |

The "never copies" invariants (verified by grep):

- Spec 004, explicit non-behaviours: "Does not copy, move or modify the audio files that a playlist refers to." and "Does not back playlists up or sync them; that is the person's choice via iCloud Drive."
- Spec 004, constraints: "the app does not itself back up or sync them."
- Spec 005 `prd.missing.untouched`: searching never moves, renames, copies or modifies any file.
- Spec 004 `prd.playlist.audio_untouched`: Remove never touches the audio file.

This feature contradicts the first two on purpose, and only after consent. Section 12 lists the amendments.

## 3. Decisions

### 3.1 What syncs, and where (question 1)

**Decision: one app iCloud container, public in Files and Finder. It holds playlists and audio. Nothing else.**

```
iCloud Drive/
  Playaway/                         (the container's Documents folder, public)
    Playlists/
      Dinner.lplaylist
    Audio/
      <name of the folder the file came from>/
        01 Intro.mp3
```

| Item | Rule |
|---|---|
| Playlists | Live in `Playlists/`. The file name is the playlist name, as today. |
| Audio | Copied into `Audio/<source folder name>/`. One folder level keeps albums grouped and keeps Files browsable. A name collision with different content gets a numeric suffix. A file with the same size and the same SHA-256 already in the container is reused, not copied twice. CryptoKit is already used in the repo (`SparkleConfigTest`, per the iPhone doc), so hashing adds no dependency. |
| What does not sync | Settings (shuffle, repeat, volume), hazard marks, window state, the Open Recent list. Each device keeps its own. |
| Visibility | `NSUbiquitousContainers` in both `Info.plist` files, with `NSUbiquitousContainerIsDocumentScopePublic` true and a name. The key names are from my memory of Apple's documentation: unverified (verify in S1 by seeing the folder in Finder and in the Files app). |
| Container id | `iCloud.<reverse-DNS chosen by the owner>`. It is not tied to a bundle id, so the Mac app (`com.localplayer.app`) and the iPhone app (bundle id still undecided, iPhone doc Q11) can both list it as long as they share a team. Unverified. |
| Membership | A playlist is "synced" if and only if its file is inside the container. There is no flag in the file and no sync database. Moving a playlist in or out in Finder changes its membership. |
| Audio dropped in by hand | A person can drag audio into `Audio/` in Finder or Files. Adding such a file to a playlist copies nothing: its canonical path is already inside the container, so the reference is container-relative. |

Alternatives rejected:

| Alternative | Why rejected |
|---|---|
| User-chosen iCloud Drive folder as the primary | The Mac is unsandboxed (verified), so it could use any path with no entitlement and no profile. That is its real advantage and it is the main reason to keep it as the fallback. But the iPhone has to be handed that folder through the document picker and a security-scoped bookmark, once per device, and it breaks if the person renames or moves the folder. The container needs no setup on the phone and cannot be moved by the person. "Works the same on both" favours the container. |
| Playlists in the container, audio left in place and referenced | Audio would not reach the phone. Defeats the feature. |
| Sync the whole `~/Music` or any user folder | The app has no library concept (verified, spec 004). Syncing folders the app does not own is a much larger consent. |
| Hidden container (not public) | Files and Finder would not show it. The person could not see or remove what the app put in their iCloud. Fails the trust goal. |

**Fallback, chosen only if S1 fails.** If a Developer ID app with the hardened runtime cannot use an iCloud container (section 7), the Mac side switches to a user-chosen iCloud Drive folder, with the same layout under it. The reference model (section 5) is relative to a `SyncRoot`, so only the root's source changes: container URL, or a folder URL plus, on iPhone, a bookmark. The design is therefore reversible at the cost of the iPhone setup step.

### 3.2 The invitation (question 2)

**Decision: three entry points, one of them passive and shown at most once. No entry point does anything but open the consent flow.**

| Entry point | Behaviour |
|---|---|
| File menu, "iCloud Sync…" (Mac). On iPhone, the "…" menu in the Playlists navigation bar, "iCloud Sync". | Always present. Opens the sync window (below). Disabled with a reason line when sync is unavailable (section 7). |
| The sync window (the "settings pane") | Shows state and the one primary action: Turn On, or Turn Off. It is where the invitation lands. |
| The invitation sheet | Offered once per device, only when all hold: sync is available (signed in, entitled), the person has saved a playlist with at least one track, nothing is playing, and the first window has been on screen (so it never delays launch, spec 006). It is attached to a playlist window as a sheet and is transient like `Notice`. |

Rejected triggers:

- First run: spec 006 wants the app usable instantly, and a new person has nothing to sync yet. Rejected.
- Every launch, or every N days: nagging. "Never forced" rules it out. I will not invent a reminder interval.
- Inside the playlist window as a banner or button: it would be a permanent element needing a job, and spec 007 says an error or notice never adds a permanent item. Rejected.
- Settings.bundle on iPhone: it cannot show a consent preview or run the copy. Rejected.

Copy (draft, to be reviewed by the owner):

> **Keep your playlists on your other devices?**
> Playaway can keep playlists you choose, and the audio files in them, in iCloud Drive, so they also play on your iPhone and other Macs. Nothing changes unless you turn this on, and you choose which playlists.
> [Choose Playlists…]  [Not Now]

"Not Now": closes the sheet and the invitation never appears again on this device. The menu item stays. The consent flow is not started. Nothing is stored except the one fact "invited". There is no "Don't ask again" checkbox because "Not Now" already means that. This is a decision, not a verified preference: a one-shot invitation may under-convert, and the owner can choose to allow one reminder (question 3 in section 13).

**The sync window** is one small window, kind `sync`, with three states:

| State | Shows |
|---|---|
| Off | One sentence of what sync does, the Turn On button, and the reason when unavailable. |
| Working | A status line ("Copying 3 of 12 files", "Uploading", "Waiting for iCloud") and a Cancel button. |
| On | Status line, the count of synced playlists, "Add Playlists…", and Turn Off. "Reveal in Finder" (Files link on iPhone) so the person can see and delete their own data. |

Turning it **off later**: Turn Off in the same window, with one confirmation that states what does not happen (section 4.5).

**Fit with spec 007.** The three-jobs rule as written governs the playlist window (spec 007 "Out of scope: any window other than a playlist window"; open question 4 asks whether menus and dialogs fall under it). Honest options:

| Option | Consequence |
|---|---|
| A. Treat sync UI as outside spec 007, as menus and dialogs may be. | Zero spec change. Contradicts the project's spirit: nothing would check the sync window for stray items. |
| B. Add `sync` to `WindowKind`, record the sync window's elements in `ui-manifest.json`, and assign each to the existing job `manage_playlists`, widened in wording to "manage playlists, including where they are kept". | No fourth job. Requires a one-sentence change to spec 007's job description and code in `UIManifest` (`WindowKind`), `ManifestChecker` states and `WindowEnumerator`. |
| C. Add a fourth job "keep playlists in sync". | Rejected: the code comment and the PRD both say the set of three is closed; the jobs describe what the person does with music, and sync is a way to keep playlists, which is job three. |

**Recommendation: B.** Elements to record under `sync`: `sync.status`, `sync.turnon`, `sync.turnoff`, `sync.cancel`, `sync.addplaylists`, `sync.reveal`, plus the consent sheet's `sync.consent.list`, `sync.consent.total`, `sync.consent.confirm`, `sync.consent.cancel`, and the invitation's `sync.invite.choose`, `sync.invite.notnow`. States for the checker: `sync_off`, `sync_working`, `sync_on`, `sync_consent`, `sync_invitation`. The playlist window gains no element. This is a spec 007 amendment and an owner decision (section 13).

### 3.3 Consent to copy (question 3)

The rule the sheet is built around, stated in one line the person can check: **"Nothing you already have is moved, changed or deleted."** Audio originals stay. Playlist originals stay too. The container gets copies.

Consent is scoped to chosen playlists, not to the app. This follows from the code: the app has no list of playlists (verified), so "sync everything" has no defined set. Candidates offered in the sheet are the open playlist windows and Open Recent, plus "Add Playlists…" (an Open panel, multi-select). Nothing is preselected for playlists the person did not open this session. For the playlist from which the person came (File menu "iCloud Sync…" with a playlist frontmost, or the invitation's "Choose Playlists…") that one is preselected.

Flow:

1. **Choose.** The list of playlists with a checkbox each. Unchecked by default except the one in front.
2. **Preview.** Computed without copying, from resolving each chosen playlist's tracks (the same `TrackResolver`, on a background queue like `resolveStatuses`):
   - number of playlists, number of audio files, total bytes (`fileSizeKey`), after removing files already identical in the container;
   - tracks that are missing and will be left as they are (they keep their local reference, section 5);
   - bytes needed on this Mac's disk (copies are local files too; the originals are not removed). Free local space comes from a volume resource key I believe exists (`volumeAvailableCapacityForImportantUsageKey`): unverified, verify in S4;
   - **no iCloud free-space figure.** I know of no public API that reports iCloud quota (unverified; S4 checks). The sheet says how much will be added and points the person to System Settings for their plan. It does not claim the amount fits.
3. **Confirm.** The sheet's text, with the real figures in place of the placeholders:

   > Playaway will copy **<N> audio files (<size>)** and **<P> playlists** into iCloud Drive > Playaway.
   > Your original files and playlists stay where they are and are not changed. The copies use iCloud storage and disk space on this Mac.
   > After this, audio you add to a synced playlist is copied into iCloud too.
   > You can turn this off later. Turning it off does not delete anything.
   > [Cancel]  [Copy and Turn On]

   The last-but-one sentence is the standing consent for later adds (section 4.3). Without it, a later add would copy without the person having agreed to that.
4. **Run.** Per file: copy to a staging location, verify size and SHA-256 against the source, then place into the container. Playlists are written last, so a playlist never lands in the container before its audio. (Whether iCloud preserves that order to other devices is not guaranteed; section 4.4 covers the case where it does not.)
5. **Cancel.** The button stops after the file in progress, which is discarded. Files already copied stay in the container (the app does not delete what it put in iCloud; a retry reuses them through the same-content check). Playlists not yet written are not written. The status line says "Stopped: 7 of 12 files copied" and nothing else.

Two phases, shown separately, because they behave differently:

| Phase | Controlled by | Signal |
|---|---|---|
| Copy into the container | This app and the local disk | Progress in the app (bytes copied). A local-disk error stops it with a message. |
| Upload to iCloud | The system | Per-item upload status via `NSMetadataQuery` keys (`NSMetadataUbiquitousItemIsUploadedKey`, `...UploadingErrorKey` and similar names; unverified, S4). The app only reports it. |

This matters because **a quota-exceeded condition will not fail the copy.** The copy succeeds locally and the upload fails later and asynchronously. So:

- Quota exceeded: the status line says "N files could not be uploaded: iCloud storage is full". Playlists using them keep working on this Mac. On other devices those tracks show the not-downloaded state (section 5) and never download. The app takes no automatic action: it does not delete anything, does not retry in a loop, and does not remove the track from the playlist. Verifying how the upload error surfaces needs a full account (S4).
- Signed out of iCloud, at turn-on: Turn On is disabled with the reason "Sign in to iCloud in System Settings". Detection: `FileManager.default.ubiquityIdentityToken == nil`. Unverified; verify in S6.
- Signed out or account changed after turn-on: the app observes `NSUbiquityIdentityDidChange` and moves to a state "needs attention". It stops copying and reading the container. Synced playlists open if their files exist locally and show the rest as missing (existing 005 behaviour). The person must turn it on again, which repeats consent. Data is never moved between accounts. What macOS does with the local copy of container files on sign-out is unverified (S6).

### 3.4 Turn Off and originals (sections 3.3 and 4.5)

Turn Off deletes nothing in iCloud, nothing local, and rewrites no playlist (a rewrite would itself sync to the other devices). It sets this device's flag off. Consequences, stated in the confirmation:

> Turning off stops copying and keeping playlists up to date on this Mac. Your files stay in iCloud Drive > Playaway, and playlists that point to them keep working while those files are on this Mac. To remove them, delete the folder in iCloud Drive.

While off, a playlist that was synced and opens again still resolves its container-relative tracks as long as the container is reachable (the entitlement still exists). Auto-copy and the standing consent end. New files added to such a playlist are referenced in place like any local playlist (nothing copied), and so will not play on other devices. That is the same as pre-sync behaviour for a playlist.

## 4. Reference model, resolution and migration (question 4)

### 4.1 The new reference

`TrackReference` gains two optional fields:

```
containerPath: String?   // "Audio/<folder>/<file>", relative to the container Documents folder
fileSize: Int64?         // bytes, for confirming a candidate
```

Both are optional, so the synthesised `Codable` decodes files without them and omits them when encoding `nil` (standard behaviour of synthesised optionals; unverified against this Swift 6.2 toolchain, the golden-file test in section 10 proves it). The existing `bookmark`, `lastKnownPath` and `fileName` stay.

For a track whose file is in the container, the writer stores `bookmark` as empty data and `lastKnownPath` as an empty string. Reason: those two values are device-local. If every device refreshed its own bookmark and path into the shared file (`TrackResolver.refreshed` does this today whenever the path or staleness changes), each open would rewrite the file and the devices would fight through iCloud, producing conflicts from nothing. An empty bookmark already falls through `TrackResolver` safely (`try?` on resolving it, and an empty `lastKnownPath` is checked with `!ref.lastKnownPath.isEmpty`; both verified).

### 4.2 Resolution order

`TrackResolver` gets an injected optional `SyncRootProviding` (nil when sync is off or unavailable, which makes it behave as today).

1. If `containerPath` is set and a root exists: the candidate is `root/containerPath`. Present and downloaded: `.resolved(url)`, reference unchanged and never refreshed. Present but not downloaded: `.resolved(url)` plus availability `.notDownloaded` or `.downloading` (4.4). Absent: step 2.
2. Container-only tree match (4.3).
3. If the bookmark is non-empty: as today. If `lastKnownPath` is non-empty: as today. Else `.missing`.

On iPhone the iPhone design's `ReferencePolicy` already disables the `lastKnownPath` fallback; step 1 and 2 come first on both platforms and are the same code (it belongs in the shared core).

`TrackStatus` is unchanged (two cases), as the iPhone design also chose, so `PlaybackGate` and every `switch` stay valid. Availability is a separate in-memory value (4.4).

### 4.3 If the person moves or renames something inside the container

The container is public, so the person can reorganise it in Finder or Files. A stale `containerPath` then falls to a recursive name match over the container tree only. This is a deliberate extension of story 005, which matches by file name only in the direct children of one folder and puts renames and sub-folders out of scope.

| Rule | Detail |
|---|---|
| Scope | The container's `Audio/` tree only. Never anywhere else. |
| Match | `fileName`, case-insensitive, as `FolderMatcher` does. `FolderMatcher` itself is unchanged. A new `ContainerTreeMatcher` conforms to the same style of protocol and recurses. |
| Disambiguation | If exactly one candidate: relink. If several: keep those whose size equals `fileSize`. If exactly one remains: relink. Otherwise stay missing. 005's "never guess" is kept. |
| Write-back | The relink updates `containerPath`, through the normal `apply` path (so it autosaves like any repair). |
| Read-only | The search lists directories only. The "untouched" rule holds. |

Fingerprint: the iPhone doc suggested name plus size plus duration. Duration needs the file opened, which an evicted file does not allow, so the fingerprint here is name plus size. A content hash is used only at copy time (the same-content check), not at resolution, because hashing needs the file downloaded.

### 4.4 Adding tracks and Locate in a synced playlist

- **Add Files** to a playlist whose file is inside the container: each file outside the container is copied (stage, verify, place) and the track gets a container reference. If the copy cannot be made (local disk full, container unavailable, cancelled), the file is not added and a new `Notice` case (`Notice.syncCopyFailed`) is shown through the existing notice path, which keeps the same one-Dismiss shape as `unsupported`. A track with a local-only reference is never added to a synced playlist, because it would be missing everywhere else.
- **Locate** in a synced playlist: the open panel starts in the container's `Audio/` folder. A file picked outside the container goes through a one-file version of the consent sheet before it is copied. This is the only way a "located" track stays resolvable on the other devices.
- Existing local playlists with sync on: unchanged, and not synced, until the person chooses them in the consent sheet.

### 4.5 File format compatibility

| Case | Version written |
|---|---|
| No track has `containerPath` (every file made with sync off, and every file made by an older build) | `1`, byte-identical to today |
| At least one track has `containerPath` | `2` |

Decision and reason. `PlaylistStore.load` returns `.unsupportedVersion` for anything above 1 (verified). An older Mac build opening a synced file would, if the file stayed at version 1, ignore `containerPath`, read the empty bookmark, show every track missing, and **on any later refresh or Locate re-save the file without `containerPath`**, silently stripping the sync information for every device. A refusal is safer than a silent strip. So files that rely on `containerPath` are written as version 2, and older builds refuse them with the existing "made by a newer version" message (verified text in `PlaylistDocument.read`).

This reverses the iPhone doc's rejection of a version bump (its option 3), for a narrower reason: that doc rejected bumping the format for every file; this bumps only files that contain container references, which only exist after the person opted in. New builds read versions 1 and 2. A build that cannot read 2 never sees a sync-off playlist as 2.

Rejected: staying at version 1 and relying on old builds ignoring unknown keys. Ignoring is correct for reading and wrong for rewriting, as above.

`PlaylistStore.save` also changes in two ways that matter only inside the container, both gated by "the destination is in the container":

- Do not rewrite when the encoded bytes equal the file's current bytes (the encoder is deterministic with `.sortedKeys`, verified), which stops pointless sync traffic.
- Do not put the `.lpsave-*` temporary beside the file. The temporary would be an uploadable file in a public folder. Use `FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)` as the temporary location, the API `replaceItemAt` is designed around. Whether the system uploads or shows a dotfile temporary is unverified; this removes the question (S3).

### 4.6 Migration of existing local playlists

There is no automatic migration. A local playlist becomes synced only when the person selects it in the consent sheet. For each selected playlist:

1. Resolve its tracks. Missing tracks stay in the copy with their existing local reference and are listed in the preview. Present tracks are copied (3.3) and get container references with empty bookmark and path.
2. Write the new playlist into `Playlists/` (name collision: numeric suffix, never overwrite).
3. If the playlist is open in a window, the window's document is closed and the copy is opened in its place, at the same window position. Undo history of the old document is not carried over (decision; the alternative `NSDocument.move(to:)` would move the person's file, which the "nothing is moved" rule forbids).
4. The original `.lplaylist` is left untouched, so the person now has two files named alike, one local and one in iCloud. The consent text says so. Deleting the old one is "in Finder", which is spec 004's existing stance ("the person deletes the playlist file in Finder").

Rejected: moving the playlist file (one file, no duplicate), which would be tidier but changes a file the person owns and breaks Finder aliases, Open Recent and any backup. Rejected: converting the playlist in place so that it syncs wherever it is: the file would have to be in the container anyway.

## 5. File states, conflicts, offline (question 5)

### 5.1 Availability

A separate in-memory store (like `TrackStatusStore`, never written to disk):

| Availability | Meaning | Source |
|---|---|---|
| `local` | Downloaded and readable | `ubiquitousItemDownloadingStatus == current` |
| `downloading` | The system is fetching it | metadata query, downloading status and percent |
| `notDownloaded` | Placeholder or evicted | downloading status not current |
| `unreachable` | Container unavailable (signed out, account changed) | identity token |

`TrackStatus.resolved` is unchanged, so the gate and every existing test stand. Whether an evicted file on macOS 26 is a dataless file (the path exists and the first read blocks) or a `.name.icloud` placeholder (the path does not exist) changes how `isPresent` behaves: the first reads as present, the second as missing. I do not know which applies. S2 decides it. The design handles both: resolution looks for the placeholder name as well, and never concludes `.missing` for a file that has a placeholder.

What happens today if a stub is played: `FormatClassifier` reads it, fails, `PlaylistPlayer.attempt` marks it unreadable and skips (verified path). With sync on, the gate for container tracks becomes: `local` plays; `downloading` and `notDownloaded` do not reach the classifier (so they are never marked as hazards or "unsupported"); `unreachable` is treated as missing.

### 5.2 What the person sees

No new window element and no new job. The row and the transport's existing now-playing label carry state. Precedent: the playing marker and hazard icon are row decorations and have no manifest entry (verified). If the owner reads spec 007 strictly, add one element `playlist.track_state` for `manage_playlists`. New checker state: `track_not_downloaded`.

| Situation | Track row | Transport |
|---|---|---|
| Downloaded | As today | As today |
| Not downloaded | A cloud glyph beside the name. Text stays normal, not greyed (greyed means missing). | Nothing changes. |
| Downloading | A progress glyph (determinate if the system reports percent, else indeterminate) | Nothing changes unless this is the track the person asked to play (next line). |
| Person double-clicks (Mac) or taps (iPhone) a not-downloaded track | Starts the download. Row shows downloading. | The now-playing label shows the track name and "Downloading…". Position, elapsed, remaining and Play/Pause are disabled, as with nothing playing. When the file is ready it plays, unless the person has chosen another track or paused in the meantime. |
| Download fails or no network | Cloud-with-slash glyph for the session, no dialog (005's "no dialog" rule) | Label returns to its previous state. |
| Missing (no file anywhere) | Greyed, hazard when skipped or tried: as today | As today |

The label text "Downloading…" is new copy on an existing element. The disabled states already exist for nothing-playing.

### 5.3 Autoplay onto a track that is not downloaded

This answers iPhone Q4 with a recommendation: **skip it, like a missing track, and start its download.** `PlaylistPlayer.playLoop` already skips refused tracks and is bounded by track count (verified), so the music does not stop (005 `prd.missing.autoskip`). Two differences from a missing track: the mark is the cloud glyph, not the hazard (the file is fine, the network is not), and the track is eligible again on the next pass because the mark is session-only.

Prevention is better than skipping: when a track starts, the player requests download of the next track(s). Lookahead count is a named constant, initially one, to be set after S5 shows how long downloads take on a device. If every remaining track is not downloaded, playback stops with the row states visible, as it does today when nothing is playable.

Waiting for an in-flight download instead of skipping is an alternative; a bounded wait needs a timeout value I cannot justify without S5. Owner question 5.

### 5.4 Offline

- Downloaded tracks play offline. Not-downloaded ones show the cloud glyph and cannot play.
- The app does not try to detect "offline". It reports what the file system reports.
- The app does not "pin" files. A public API to keep a file permanently downloaded is not known to me (unverified); the person can use Keep Downloaded in Finder or Files.
- "Download playlist" (fetch every track of one playlist ahead of time) is a phase 3 action, with the same preview (bytes) as the consent sheet and, on iPhone, a note about cellular data. It needs the same parity entries as everything else in section 8.

### 5.5 Conflicts

Audio files: the app never writes them after the copy, so they do not conflict.

`.lplaylist` conflicts happen when two devices change the same playlist before syncing. Detection: `NSFileVersion.unresolvedConflictVersionsOfItem(at:)` on open, and the metadata query's has-conflicts flag while open (unverified names; S3).

**Merge rule (two-way, by track id):**

| Part | Rule |
|---|---|
| Version order | Sort versions by modification date, then by encoded bytes as a tie-break, so every device computes the same result from the same inputs. |
| Track set | Union by `id`. |
| Order | The newest version's order is the spine. A track only in an older version is inserted after the nearest preceding track of its own version that exists in the spine, or at the start if none. |
| Same id, different reference | Prefer a container reference over a local-only one. Then prefer one with `fileSize`. Then the spine's. |
| Removals | Not preserved. A track removed on one device and present on the other comes back. This is a known limitation of a merge with no common ancestor: the file versions available do not include a base. Removing is cheap for the person, losing a track silently is not. If this proves annoying, add an optional `removedTrackIDs` list in a later format revision (decision deferred, not designed). |
| Corrupt version | Left unresolved and not deleted. The good version stays current. |
| After the merge | Write through the normal store (coordinated), mark the other versions resolved and remove them. |

Silent by design: no dialog (consistent with 005). The sync window shows "Last merge: <time>" in the On state so the person can see that it happened.

Rejected: last writer wins with the loser kept as a sibling file "Dinner (conflict).lplaylist": it would appear in Files and Finder, lose edits without telling, and clutter the playlist list. Rejected: ask the person which version to keep: a dialog on a background event, against 005's no-dialog stance, and the person cannot judge two JSON files.

Same name created on two devices: the system keeps both files with different names. They are two independent playlists and nothing merges them. Renames are file moves, so a rename conflict also surfaces as two names. Unverified behaviour; S3.

## 6. Coordination and autosave (question 6)

| Concern | Design |
|---|---|
| Who reads and writes | Reads of `.lplaylist` go through `NSDocument`, which coordinates on its own (unverified in detail; S3 confirms with a log). `PlaylistStore.save` already uses `NSFileCoordinator` `.forReplacing` (verified). New code that touches container files outside a document (copy, merge, tree match, status) uses `NSFileCoordinator` for every read and write. |
| Presenters | An open `PlaylistDocument` is an `NSFilePresenter` through `NSDocument` (unverified; S3). The app adds no presenter for the container root. |
| Remote change while the document is open | Expected: `NSDocument` calls `read(from:ofType:)` again when its file changes under it and the document has no unsaved edits. The existing `read` replaces `playlist` wholesale and, today, does not republish `changes`. So: after a remote reload, re-run `resolveStatuses` and send `changeSubject`, so the window and the player see the new list. The `PlaylistPlayer` reads the playlist through a closure each time (verified: `playlist: { [weak self] in self?.playlist ?? Playlist() }`), so a playing session continues; a current track that disappeared is an open case to design in phase 2 (suggestion: finish the current track, then follow the new order). |
| Remote change while the document has unsaved edits | `scheduleAutosave` writes on the next main-queue turn, so the window of unsaved edits is short. If both sides changed, iCloud produces a conflict version and section 5.5 merges it. Whether `NSDocument` would instead show its "changed by another application" sheet is unverified. If it does, it breaks the no-dialog rule and must be intercepted by overriding the relevant presenter callbacks. S3 must observe this. |
| Autosave churn | No write when bytes are unchanged (4.5). `apply` already skips equal references (verified). Container references are never refreshed (4.2). Together these mean: opening a synced playlist writes nothing. A test asserts it. |
| Status for the sync window and for rows | One `NSMetadataQuery` per sync session, scope `NSMetadataQueryUbiquitousDocumentsScope`, observing downloading, percent downloaded, uploading, uploaded and error keys for items under `Audio/` and `Playlists/` (names unverified). It runs only while sync is on. With sync off it is never created. |
| Threading | Copy, hashing, tree matching and merging run off the main thread, like `resolveStatuses`. Results hop to the main thread. Nothing here is in the audio render path. Zero allocation rules for the render path are untouched: no code in this design runs there. |
| iPhone | `UIDocument` already coordinates and reloads on change (unverified; the iPhone doc makes the same assumption). The codec split from the iPhone doc (pure `encode`/`decode`) is where version 1 and 2 live, so both platforms share them. |

## 7. Entitlements, signing, distribution (question 7)

**Today (verified).** Not sandboxed, hardened runtime, Developer ID, notarised, DMG, Sparkle. Entitlements: `network.client` only. `build-app.sh` has a gate against the sandbox key. No provisioning profile is involved anywhere in the pipeline. `bundle-dev.sh` uses an ad hoc signature with no entitlements.

**What iCloud needs (all unverified; S1 verifies):**

| Need | Detail |
|---|---|
| Entitlements | `com.apple.developer.icloud-container-identifiers`, `com.apple.developer.ubiquity-container-identifiers`, and, I believe, `com.apple.developer.icloud-services` for the document container. Names from memory. |
| Provisioning profile | iCloud entitlements are restricted, so I believe a Developer ID provisioning profile with iCloud enabled must be embedded as `Contents/embedded.provisionprofile`. Without it I expect the system to kill the app at launch, not merely disable sync. This is the sharpest hazard in the whole design: the change to the entitlements file must ship together with the profile, never alone. |
| App ID | The Mac app's App ID and the iPhone app's App ID must both have the same container enabled, in one team. |
| Sparkle | Unaffected in principle: the notarised app is signed inside-out as now, and the entitlements and profile apply to the outer app only. Sparkle's updater replaces the whole bundle, so the profile travels with the update. Untested. |
| Hardened runtime | Does not conflict with iCloud as far as I know. Untested. |

**Changes to the release pipeline, if S1 passes:**

- `build-app.sh` copies the profile into the bundle before the final `sign` step and has a preflight that fails when the entitlements file lists an iCloud key but no profile is present (the mirror of its sandbox gate).
- `validate_entitlements` keeps rejecting the sandbox key.
- A new test next to `ReleaseScriptTests` asserts the preflight and that `LocalPlayer.entitlements` and the iPhone entitlements name the same container.
- The entitlements file used for the dev bundle remains the one without iCloud (below), so that a missing profile cannot break development.

**What the ad hoc dev bundle cannot do.** `bundle-dev.sh` signs with `--sign -` and no entitlements, so `FileManager.url(forUbiquityContainerIdentifier:)` returns nil (expected, unverified). Sync is "unavailable in this build". The menu item is disabled with that reason, the script status reports it (section 8), and every sync code path is reachable only through the injected fake container. Consequence for testing: all logic is tested against a temp folder; the real iCloud behaviour needs a properly signed build on a real Apple ID (section 10). The e2e suite uses `bundle-dev.sh` with another bundle id (verified); it will not exercise real iCloud.

**Distribution fallback if S1 fails.** Mac App Store distribution would force the sandbox, which the repo rules out for Sparkle. The fallback is the user-chosen folder in 3.1: the unsandboxed Mac reads iCloud Drive by path with no entitlement. macOS may show a privacy prompt for iCloud Drive access (unverified; S1 notes it).

**iPhone.** Signing is by the Xcode project the iPhone design already plans. Add the iCloud capability (Documents) there with the same container id. TestFlight and App Store builds carry the profile automatically in Xcode-managed signing (unverified).

## 8. Automation parity (question 8)

The project rule (spec 009 `prd.script.parity`, `prd.script.parity_gate`, `prd.script.tested`): every on-screen action has a script command or read-write property, the build fails otherwise, and both routes are tested. The release gate parses the sdef for commands and read-write application properties (verified in `ParityGate`).

### Consent must hold for scripts

A script cannot "see" the sheet, so consent is made explicit and tamper-evident rather than skipped:

1. `preview icloud sync` returns the same numbers the sheet shows (files, bytes, missing tracks, playlists) and a **consent token**. The token is derived from the exact set and sizes in the preview.
2. `start icloud sync` requires that token. If the set or sizes changed since the preview, it is refused (error 1010) and the script must preview again.
3. The sheet's "Copy and Turn On" button is the same call with the token of the preview the person saw. One code path, so click and script cannot drift (the same design as `AppActions` today, verified).

A script therefore cannot turn on copying without having read what will be copied, and cannot confirm a stale preview.

### Action manifest entries

| Action id | UI binding | Script (sdef) | iOS App Intent |
|---|---|---|---|
| `syncPreview` | File > iCloud Sync… (sheet shows the preview) | command `preview icloud sync` (optional list of playlist names; default: the open playlists) | `PreviewSyncIntent` |
| `syncStart` | "Copy and Turn On" | command `start icloud sync` (parameters: `consent token`, playlist names) | `StartSyncIntent` (needs the token; opens the app) |
| `syncCancel` | Cancel in the sync window | command `cancel icloud sync` | `CancelSyncIntent` |
| `syncStop` | Turn Off | command `stop icloud sync` | `StopSyncIntent` |
| `syncAddPlaylists` | Add Playlists… in the sync window (re-runs preview and consent) | `preview icloud sync` plus `start icloud sync` (covered) | same |
| `syncReveal` | Reveal in Finder / Files | none (a view action; the parity gate counts actions with an on-screen binding, so this needs either an entry or an exclusion with a reason. Decision: add `reveal icloud folder`, cheap and honest.) | `RevealSyncFolderIntent` (opens the app) |
| `downloadPlaylist` (phase 3) | Download playlist | command `download playlist` | `DownloadPlaylistIntent` |

Read-only application property `icloud sync status` (text): one of `unavailable`, `off`, `copying`, `uploading`, `up to date`, `needs attention`. Read-only properties are not counted by the parity gate (it takes `rw` properties only, verified), but spec 009 `prd.script.state` already requires reads to be available. A second read-only property `icloud sync detail` carries the counts and the reason. A track-level read: track class property `availability` (`local`, `downloading`, `not downloaded`, `missing`), read-only.

New error numbers (the list in `ScriptError` is flagged as changeable before the first release, verified): 1009 `syncUnavailable` (not entitled, signed out, no container), 1010 `consentRequired` (no token, or the token is stale), 1011 `syncBusy` (a copy is already running), 1012 `syncCopyFailed`. Each refusal changes nothing, as 009 requires. Messages are plain language and shared with App Intents through `ScriptFailure`, as the iPhone doc plans.

Both routes are tested for every row: UI route through the sheet and window, script route through the command, same final state asserted from the same model (like `DualPathTests`; the iPhone doc notes it imports AppKit, structure not read). In the dev bundle both routes run against the fake container.

Disabled states and the gate: when sync is unavailable, the menu item is disabled and `preview icloud sync` returns 1009, so the refusal in the UI route and the script route match.

The iPhone parity gate (the iPhone doc section 10) gets the same rows with their `intentBinding`; `startSync` on iPhone uses `openAppWhenRun` because a background intent cannot reliably run a long copy (unverified; S5).

## 9. Privacy and failure modes (question 9)

### Privacy

| Topic | Position |
|---|---|
| Where the data goes | Into the person's own iCloud account, through the system. The app has no server, no analytics and no new network use (verified: only `network.client` for Sparkle). The developer has no access to the contents of a person's container (my understanding of iCloud Drive; unverified). |
| What is in the playlists | File names and, for local references, absolute paths that may contain the person's user name and folder names. Container references carry empty paths, so synced playlists do not export the local path layout. A migrated playlist that still has a missing track keeps that track's local path (4.6): disclose in the sheet that missing tracks keep their old reference. |
| Audio rights | The files are the person's own, copied to their own account. The app only shows the preview. No copy is made without consent. |
| Consent record | One device-local flag, `sync.enabled`, and one "invited" flag, in `UserDefaults` (the repo already stores play modes and volume that way, verified). Neither syncs. Each device opts in separately. |
| Logs | The status and last-merge information is kept in memory and the sync window. Nothing logs file names off the device. |
| iOS privacy manifest | The iPhone doc already plans one; the container adds no tracked data. Re-verify with Xcode's privacy report. |

### Failure modes

| Failure | Behaviour |
|---|---|
| Not signed in | Turn On disabled with the reason. No copy. |
| Signed out later, or account changed | State "needs attention". Reading the container stops. Playlists show unreachable tracks as missing. Re-enabling repeats consent. Nothing deleted. |
| iCloud storage full | Local copy completes, upload fails, status line reports the count, no auto-retry loop, no deletions, playlists keep working here (3.3). |
| Local disk full while copying | The copy stops at that file. The partial file is discarded. Same-content reuse lets a retry resume. |
| Cancel | 3.3. |
| App quits or crashes mid-copy | Staging files in the temporary directory are discarded on next launch. Placed files are complete (stage, verify, place). Playlists are written last, so no playlist points at a missing copy because of an interruption. On next launch the sync window shows "Stopped" and offers to run the preview again. |
| Playlist arrives before its audio | Tracks show not downloaded or, if no placeholder exists yet, missing, until the audio syncs. Existing rows states cover it. Which of the two shows depends on iCloud ordering, which I cannot verify. |
| Conflict | 5.5. |
| Corrupt or newer-version playlist in the container | Existing behaviour: refused on open, no window kept (spec 003 TC-29, TC-30). |
| Container deleted by the person in Finder | Playlists in it are gone; audio gone. Local originals remain. That is why originals are never touched. |
| Old Mac build opens a version 2 playlist | Refuses with the existing message. No strip. |
| The app is signed without the iCloud profile | Possibly fails to launch (7). Caught by the release preflight. |

## 10. Testing strategy (question 10)

### What can be tested without iCloud

Put the logic behind protocols and test it against a temp folder. All of these run in `swift test`:

| Area | Tests |
|---|---|
| Golden file | With sync off, a playlist encodes to the same bytes as today for several fixtures (the corpus in `Tests/Fixtures` plus empty and 5-track playlists). Decode of a stored version 1 file is unchanged. This is the "nothing changes" proof. |
| Codec | Version 2 round trip. `containerPath` and `fileSize` absent when nil. Version rule (1 unless a container reference exists). Version 3 is `.unsupportedVersion`. A version 1-only reader fixture refuses version 2 (simulated by the old rule). |
| Resolver | With a fake `SyncRootProviding` over a temp dir: container-relative resolves; empty bookmark and path are safe; container reference is never refreshed (no `apply` call); moved or renamed file inside the tree is found by name and by size; two same-name candidates stay missing; a path outside the container is not searched. |
| Copy planner | Same-content reuse, name collision suffix, preview numbers equal what the copy then does, cancel discards the in-progress file, interruption leaves no playlist, verify catches a corrupted copy (inject a faulty copier). |
| Merge | Union, order insertion, tie-break determinism (apply the merge in both orders on two simulated devices and require identical bytes), corrupt version left alone, reference preference, removals resurrect (a test that documents the limitation). |
| Autosave churn | Opening a synced playlist writes nothing. Saving unchanged bytes writes nothing. |
| State machine | Availability transitions with a fake metadata source. Gate does not mark a downloading track as unreadable. Autoplay skips a not-downloaded track with the cloud mark, not the hazard. |
| Consent | A token from one preview does not authorise a changed set. The sheet and the script reach the same function. |
| Scripting | Parity gate passes with the new commands and fails if one is removed. Both routes for each action. Disabled in the unavailable state through both routes. |
| Manifest | The `sync` window kind and states pass the checker with every element recorded. |
| Release | The new preflight in `build-app.sh` (using the repo's shim pattern for tool commands, verified in the script header). |

### What cannot be verified without a real iCloud account and a device

- That the Developer ID build with the profile launches and gets a container (S1).
- Real upload, download and eviction behaviour, including whether evicted files are dataless or placeholders (S2).
- Conflict creation, the content of `NSFileVersion`, and `NSDocument` reaction to remote changes (S3).
- Quota-full behaviour and any way to read free iCloud space (S4).
- Background download and lookahead timing on iPhone (S5).
- Sign-out, account switch, and what happens to local container copies (S6).
- Files and Finder visibility of the container, the name shown, and sync latency.
- Anything cross-device. The iPhone simulator's iCloud behaviour is unreliable (the iPhone doc says the same, unverified).

A cheap second device to start with: a second macOS user account on the same Mac signed in to the same Apple ID (unverified that macOS allows it), or a second Mac.

Each item gets a manual checklist next to the iPhone doc's device checklist in `docs/`, validated by the existing `HIGChecklist` format (portable, per the iPhone doc).

## 11. Phased delivery (question 11)

| Phase | Scope | Exit criteria |
|---|---|---|
| 0. Spikes, on a real account, no production code | S1 Developer ID plus iCloud entitlement plus profile plus Sparkle plus notarisation: launches, container is created and visible in Finder and Files. S2 evicted file behaviour on macOS: dataless or placeholder, what `AVAudioPlayer` and `FormatClassifier` do on a stub, which resource keys report state. S3 `NSDocument` in the container: remote reload, any "changed" sheet, conflict creation, version API, temp-file behaviour, rename conflicts. S4 `setUbiquitous` or coordinated copy, upload error and quota surfacing, free-space APIs, local free-space key. S5 iPhone: background download for lookahead and what an intent can run. S6 sign-out and account switch. | A written result for each, with the exact API behaviour. Any design item that a result contradicts is revised before phase 1 starts. If S1 fails, 3.1's fallback becomes the plan. |
| 1. Format, resolver and engine, no UI | `TrackReference` fields, codec v1 and v2, `SyncRoot`, resolver changes, tree matcher, copy planner and copier, merge, availability store, `Notice.syncCopyFailed`; all against fakes. | Golden-file tests show sync-off output unchanged; the whole existing Mac suite passes unchanged; new tests green; no UI and no entitlement change in the same change. |
| 2. Mac enable flow | Entitlements and profile in the release pipeline plus preflight; sync window; consent sheet; copy with progress and cancel; status; Turn Off; script commands and error numbers; manifest `sync` kind; both-route tests; spec amendments applied. | Parity gate passes; on a signed build with a real account, a playlist with real audio syncs to a second device or account; Turn Off deletes nothing; checklists run. |
| 3. States and download | Availability in rows and transport label, lookahead, autoplay skip rule, "Download playlist", conflict merge wired to the live document, remote-reload handling. | Not-downloaded track never plays silently and is never called missing; remote edit appears without a dialog; merge of two real divergent edits converges on both devices. |
| 4. iPhone | Container access, the "…" menu entry, the sync screen, Home enumeration of container playlists, intents. Depends on iPhone phases 2 and 3 (iPhone doc section 16). | Cross-device acceptance: playlist made on Mac plays on iPhone and the reverse, with audio, on real hardware. |
| 5. Invitation | The one-shot sheet and its trigger. Last, so no one is invited to something unfinished. | The invitation shows once, never on launch, never while playing, and "Not Now" is final. |

Risks, ranked (highest first):

1. **Developer ID plus iCloud viability and release pipeline.** Unverified end to end. A wrong entitlement without a profile may stop the app launching for everyone. It gates the primary design and changes `build-app.sh`, whose tests exist (`ReleaseScriptTests`, `MinOSConsistencyTests`). Mitigation: S1 first; preflight; fallback to the user-chosen folder.
2. **Data integrity under sync.** Conflicts, merge with no base (resurrected tracks), older builds stripping fields (handled by version 2), and any `NSDocument` behaviour that overwrites or prompts. A silent bad merge on a person's playlist is the worst user-visible result. Mitigation: deterministic merge, tests, S3.
3. **Consent honesty and quota.** Upload failure is asynchronous and quota cannot be previewed (as far as I know). The person may believe "synced" while the other device never receives files. Mitigation: two-phase status, honest copy, no claim of fit; limited by what S4 finds.
4. **Evicted-file semantics unknown.** `isPresent`, `FormatClassifier`, and `AVAudioPlayer` may each behave differently on stubs and placeholders. Wrong handling shows as intermittent "unreadable" tracks, which erodes the trust story 005 is built on. Mitigation: S2 and the gate rule in 5.1.
5. **Spec churn.** Specs 004, 005, 007 (and 006 for the invitation timing) all need amendments. Doing the code first and the specs later is how the "nothing is copied" promise gets quietly broken. Mitigation: section 12 as a precondition for phase 2.
6. **Disk and expectation cost.** Copies double local disk use on the Mac while originals remain. Mitigation: disclosed in the sheet; reported figure.
7. **Testing gap.** Most real behaviour cannot be asserted in CI. Mitigation: heavy fake-based coverage, manual checklists, and honest status in the phase exit criteria.
8. **Discoverability on Mac.** There is no list of playlists (spec 004), so a playlist created on iPhone is found through the Open panel, Finder, or Open Recent. Mitigation in 12 (the Open panel starts in the container when sync is on). Not a blocker, a design cost.

## 12. Spec changes this feature needs (for the owner to accept, none made here)

| Spec | Today (verified) | Change |
|---|---|---|
| 004 non-behaviours | "Does not copy, move or modify the audio files..." and "Does not back playlists up or sync them" | Add: "unless the person has turned on iCloud sync and confirmed copying. Then audio is copied, never moved or deleted, and originals are left in place." |
| 004 constraints | "the app does not itself back up or sync them" | Same exception. |
| 004 `prd.playlist.save_location` | Save panel offers Documents | With sync on, the panel starts in the container's `Playlists` folder (the person can pick elsewhere). Open panel likewise starts there. |
| 004 "no list of playlists" | Stays | Unchanged. The consent sheet's list of chosen playlists is not a library list. |
| 005 scope | Name match, one folder, renames and sub-folders out of scope, `prd.missing.untouched` | Add the container tree match (4.3) as a container-only exception. `prd.missing.untouched` is unchanged (the search is read-only). Add the not-downloaded state, which 005's design.md (line 401, verified) lists as out of scope. |
| 006 | Instant use | Note that the invitation sheet appears only after the first window is shown and never delays it. |
| 007 | Three jobs, playlist window only | Option B in 3.2: widen job three's wording, add the `sync` window kind and its elements, add the new states. |
| 009 | 19 actions | Update the count to include the new ones. The "state" requirement gets the status reads. |
| UI-IMPROVEMENTS iPhone section | "playlists could open on both" | Replace with "only with iCloud sync on". |

## 13. Open questions for the owner

Sync-specific:

1. Container or user-chosen folder? I recommend the container, gated by S1. If you would rather not touch the signing pipeline at all, the folder is the alternative with a worse iPhone setup.
2. The playlist original: leave it and copy (my recommendation, consistent with "nothing is moved") or move it (tidier, riskier)?
3. The invitation: one shot, as designed, or one reminder after an interval you choose?
4. Widen job three's wording (my recommendation) or accept sync UI as outside spec 007?
5. Autoplay on a not-downloaded track: skip (recommended), wait for a bounded time, or stop? If wait, what bound?
6. Removals in a merge: accept the resurrection limitation for the first release, or fund a tombstone field first?
7. Should "Download playlist" be in the first release, or only the lookahead?
8. Is the Mac Save and Open panel starting in the container (when sync is on) acceptable as a change to spec 004's default?
9. Container id and team (also the iPhone doc's Q11).

How this interacts with the iPhone design's open questions (`IPHONE-TECH-DESIGN.md` section 18):

| iPhone Q | Effect of this feature |
|---|---|
| 1. Should a `.lplaylist` work on both devices? | **Answered**: not by default; only with sync on. The mechanism is the optional `containerPath` and `fileSize` fields, version 2 only for files that carry them. This refines the doc's option 2 and, for this narrow case, reverses its rejection of a version bump (4.5). |
| 3. iCloud Drive as a storage location in the first release? | **Answered**: not in the iPhone's first release by default. It is this separate feature, with its own entitlement and the not-downloaded state, and it can ship after the iPhone app. The iPhone first release can ship with local playlists only. |
| 4. Not-downloaded next track during autoplay | **Answered with a recommendation**: skip with the cloud mark and start the download, lookahead prefetch (5.3). Needs your confirmation (question 5 above). |
| 2. Custom home vs system document browser | **Affected**. With sync on, the custom home must list container playlists as well as local ones, using the metadata query. Under option A the document browser would show the container for free. Recommend the same list for both, no extra element (the iPhone doc's mini and home elements already carry the job). |
| 6. Xcode project | **Affected**: the iCloud capability and entitlements are configured in that project, which favours Xcode-managed signing. |
| 11. Bundle id and team | **Affected**: both apps must share a team and list the same container id. |
| 7. Single audio files opened from Files | Not affected: opening a file from iCloud Drive through the picker does not need the container. |
| 5, 8, 9, 10 | Not affected. |

Unchanged on the iPhone doc: its section 5 table showing that a Mac-written playlist opens on iPhone with every track missing remains true for sync-off playlists, which is now the intended default behaviour, and its section 17 risk 1 is retired for sync-on playlists only.
