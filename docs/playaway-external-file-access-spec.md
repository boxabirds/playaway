# Playaway: Access to Files Outside the App Container (iOS)

## 1. Summary

Playlists can reference audio files that live outside Playaway's container (iCloud Drive, On My iPhone, third-party providers). iOS grants access to such files **per device, per user action**, not per account. A playlist created on device A will therefore reference files that device B cannot open until the user grants access on device B.

This is not a bug in the implementation, and it does not make the app class unworkable. It requires a one-time grant per device per folder, handled by a clear recovery flow.

## 2. Findings

1. **Files inside Playaway's container: no issue.** No permission is needed on any device. If the iCloud container is used, files sync. If the local container is used, files exist only on that device by definition.
2. **Files outside the container: a grant is needed on each device.** Access comes from a security-scoped bookmark created when the user picks a file or folder in a document picker. Bookmark data is tied to the device that created it and is not guaranteed to resolve on another device.
3. **The GarageBand comparison does not apply.** GarageBand has no standing access. The user chooses the document each time, and that choice is the permission. Playaway re-opens referenced files programmatically, so it needs a stored grant.
4. **It is once, not every time.** After the user grants access on a device, the stored bookmark keeps resolving across launches and restarts. It only needs repeating if the bookmark goes stale (folder moved or renamed, device restored).
5. **A file grant covers only that file. A folder grant covers everything under it.** Users add individual files, so folder-level grants must be obtained at recovery time (see section 4).
6. **Cross-device bookmark resolution is unverified.** Bookmarks to iCloud Drive items sometimes resolve on another device, but Apple does not guarantee it. Treat it as a bonus and never rely on it.
7. **The system has no "user music folder" concept on iOS.** There is no system-wide folder apps can read. The Music app library (`MPMediaLibrary`) is separate and does not expose loose files the user manages in Files.

## 3. Playlist data model

Each playlist entry stores enough information to resolve the file on any device:

| Field | Purpose |
|---|---|
| `fileBookmark` | Per-file security-scoped bookmark created at add time. Valid on the creating device only (assume so). |
| `filename` | Matching and display. |
| `parentFolderName` | Grouping in the recovery prompt. |
| `parentFolderPathHint` | Seeds the picker's starting location (see 5.2). Example: `iCloud Drive/Music/Albums/X`. |
| `relativePath` | Path relative to the granted folder, once known. Makes the entry device-independent. |
| `fileSize` | Matching. |
| `duration` | Matching and display. |
| `contentHash` (optional) | Strongest match when filename or path differs. |

Per-device (not synced) storage holds the **folder bookmarks**, keyed by a folder identifier (for example a hash of the folder's name plus path hint).

## 4. Resolve and recovery flow

### 4.1 Opening a playlist

1. For each entry, try in order:
   1. Resolve a granted **folder bookmark** on this device and append `relativePath`.
   2. Resolve the entry's own `fileBookmark` (works on the creating device).
2. If resolution succeeds, call `startAccessingSecurityScopedResource()` before use and `stopAccessing...` after.
3. If a bookmark resolves with `bookmarkDataIsStale == true`, regenerate and store a fresh bookmark from the resolved URL.
4. Entries that fail are marked **needs access**. Do not prompt per entry.

### 4.2 Recovery prompt

1. Group all unresolved entries by `parentFolderName` / path hint.
2. Show one explainer screen: "Playaway needs access to N folder(s) to restore M tracks on this device." List the folders.
3. For each folder, present the picker (section 5.2). The user taps **Open** once.
4. Store a folder bookmark for the chosen folder.
5. Re-resolve unresolved entries against the new folder:
   - Match by `relativePath` first.
   - Fall back to `filename` + `fileSize` (and `contentHash` if present) within the folder tree.
6. Any entries still unmatched remain in **needs access** with a manual "Locate file" action.

For the current user (one music folder), this is a single prompt per device, once.

### 4.3 Add-time nudge

When the user adds a file from outside the container, offer: "Also give Playaway access to this whole folder?" If accepted, store a folder bookmark immediately and record the entry's `relativePath`. This shrinks future recovery work and benefits other devices.

### 4.4 Resolve lazily

Do not block opening a playlist on resolving every entry. Resolve in a background pass or as tracks are needed. Show a **needs access** state on unresolved tracks and a non-modal banner offering the recovery flow.

## 5. Implementation notes

### 5.1 Bookmarks

- On iOS, create bookmarks with `url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)`. The `.withSecurityScope` option is macOS-only. URLs returned by the document picker carry their security scope.
- Resolve with `URL(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:)`.
- Always bracket access with `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`.

### 5.2 Folder picker

```swift
let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
picker.directoryURL = hintURL            // last known folder location, if any
picker.allowsMultipleSelection = false
picker.title = "Choose your Music folder"
picker.delegate = self
present(picker, animated: true)
```

- `directoryURL` (iOS 13+) sets where the picker opens, so the user usually only needs to confirm.
- It is a **hint**. An invalid URL makes the picker open at its last location, so it fails gracefully.
- iCloud Drive URLs generally have a consistent shape across devices, so the hint usually carries over. Third-party File Provider URLs may contain device-specific identifiers, so the hint may not.
- SwiftUI's `.fileImporter` has no `directoryURL` equivalent. Wrap the UIKit picker.

### 5.3 Call-to-action label

The confirm button label ("Open" in folder mode) is controlled by the system and cannot be renamed or hidden. Do not attempt to work around it. Control the surrounding context instead:

- An explainer screen before the picker: "On the next screen, tap **Open** to let Playaway use this folder on this device."
- The pre-selected folder via `directoryURL`.
- `picker.title`, which appears in some presentations.

Result: two taps ("Continue", then "Open").

`UIDocumentBrowserViewController` allows custom buttons, but it is built for picking documents rather than granting folder access, it is unconfirmed for folders, and it brings a full browser UI. Not recommended.

### 5.4 iCloud Drive eviction

Files in iCloud Drive may be evicted to the cloud. Before playback:

- Use `NSFileCoordinator` for reads.
- Call `FileManager.startDownloadingUbiquitousItem(at:)` where needed.
- Handle a "not downloaded yet" state in the UI.

## 6. Edge cases

- **Stale bookmark** (folder moved, renamed, or device restored): re-run the recovery flow.
- **Folder renamed on another device**: path hint no longer matches, so the picker opens at its default and the user navigates manually. Matching by filename + size still works after the grant.
- **Duplicate filenames in different subfolders**: prefer `relativePath`, then `contentHash`. Do not auto-match on filename alone if ambiguous.
- **User picks the wrong folder**: show how many tracks were restored and offer to pick again.
- **Third-party providers (Dropbox, etc.)**: treat the same way, but expect the path hint not to transfer.

## 7. Non-goals

- Requiring users to import music into the Playaway container.
- Prompting per track.
- Relying on cross-device bookmark portability.

## 8. Validation checklist

- [ ] Create a playlist on device A with files outside the container. Open on device B and confirm entries show **needs access** with no per-track prompts.
- [ ] Recovery prompt lists the correct folder(s) and track count.
- [ ] After one folder pick on device B, all entries resolve and play. Relaunch and confirm no further prompts.
- [ ] Confirm whether a per-file bookmark from device A ever resolves on device B (informational only, ten-minute test). Do not depend on the result.
- [ ] Check `directoryURL` behaviour on device B for iCloud Drive and for any third-party provider in use.
- [ ] Move or rename the folder and confirm stale-bookmark recovery.
- [ ] Evicted iCloud files download before playback and the UI shows the downloading state.
