# Spike notes: what the Mac sees when iCloud changes a playlist under it (story 39, task 39.5)

Written 2026-10-18 from runs on this Mac (macOS 26.6.2, Xcode 27.1) with the owner's permission. One device only: the
second device the task asks for was not available to me, so the NSFileVersion half below is what could and could not
be done from here, not observations. Everything marked **seen** was observed in a trace or a probe; everything marked
**not done** was not.

## How the probes were made

- The built debug app (`LocalPlayerE2E`, the e2e bundle) on a stand-in iCloud folder (`LOCALPLAYER_TEST_CLOUD_ROOT`).
- "The other device" was a scratch program that replaces the playlist file through `NSFileCoordinator`
  (`.forReplacing`, modification date set a moment later), which is how iCloud's daemon writes. A plain `mv` is NOT
  seen by a file presenter and must not be used to stand in for iCloud.
- The document's intake was traced with `DebugTrace` (debug builds only).

## NSDocument's reaction to a remote change (seen)

- **An opened document reloads silently.** With the playlist open and playing, a coordinated replacement of its file
  was taken in **0.81 s** (polled by script every 0.25 s): the new song appeared, the playing song was untouched, no
  sheet. No "changed by another application" sheet appeared in any run where the document had been opened from its file.
- **An unsaved edit is merged and the merge is written.** Edit by script, replace the file one second later: the trace
  shows `file changed under us: merged`, then an autosave that ends without error, and the file holding the merged list.
- **An edit that was already autosaved is not merged back.** The later file replaces ours, the document is clean and
  nothing is written. By design (task 39.9): a later version of a file that already holds our save is the other
  device's answer to it; concurrent edits arrive as conflict versions instead.
- **A playlist created in this app and never reopened is not followed.** `followed` is made only in `read(from:)`.
  A playlist made with New Playlist (or by script), synced and left open does not reload when the other device changes
  it until it is closed and reopened. Gap, not fixed here; recorded for the owner.
- **Merge of the same song under two ids.** When both versions carry the same file as rows with different track ids
  (both devices added it independently), the union merge keeps both rows. Seen once in the probe; not changed.

## NSFileVersion (not done)

Creating an iCloud conflict needs two devices editing the same playlist while one is offline; that was not possible from
this Mac alone, and `NSFileVersion.addOfItem` makes an ordinary version, not an unresolved conflict. So these remain to be
observed on the owner's two devices:

- the result of `NSFileVersion.unresolvedConflictVersionsOfItem(at:)` after such an edit;
- whether setting `isResolved = true` and calling `removeOtherVersionsOfItem(at:)` clears them, and what Finder shows;
- the latency from the other device's save to the conflict appearing here.

The code path that will handle them exists (`MacConflictVersions`, `FollowedPlaylist.resolveConflicts`) and is covered
by the fake-seam tests of task 39.2; it has not run against a real conflict.

## Related facts from the story 31 spike (same day, real container)

- Evicted files on this macOS are dataless files with their full name and size and 0 allocated bytes; there is no
  `.name.icloud` placeholder. Presence is read from `ubiquitousItemDownloadingStatus`, which works.
- Upload of a 120 KB file: 13 to 20 s. Download after an evict: 0.6 s. No percent is available to the Mac (the
  metadata query returns nothing for an unentitled process), so the Mac's pie has no fraction.
- A download started right after an evict stalled silently for the full 120 s once; the 30 s stall timeout is the
  only signal the app gets.

## The story 31 spike in full (task 31.1, run 2026-10-17 on this Mac, real container)

Setting: macOS 26.6.2 (build 25G83), Xcode 27.1, the Playaway container `iCloud~software~away~play` of the signed-in
account, a scratch program outside the repo (not committed) writing one 120,389-byte fixture into a folder of its own,
removed at the end. No product source was changed by the spike.

| Field | Seen |
|---|---|
| Status values (`ubiquitousItemDownloadingStatus`) | `Current` and `NotDownloaded` only; `Downloaded` never observed (NotDownloaded went straight to Current, with `isDownloading` true on the same read for this small file) |
| Percent downloaded | None on the Mac: the URL keys carry no percent; `NSMetadataQuery` over the ubiquitous documents and data scopes returned zero results for the container from this unentitled process; range and units stay UNVERIFIED (only an entitled iPhone process can read them) |
| Legacy `NSURLUbiquitousItemPercentDownloadedKey` | Absent (nil) |
| Upload | `isUploading` true at 0.6 s, `isUploaded` true at 13.1 s |
| Evict (`evictUbiquitousItem`) | Status `NotDownloaded` within 0.6 s; the file still exists by name with its full size and 0 allocated bytes (dataless); no `.name.icloud` placeholder |
| Download (`startDownloadingUbiquitousItem`) | Returned without error; `Current` after 0.57 s |
| Outside the container | A plain local file: `isUbiquitousItem` nil; `startDownloadingUbiquitousItem` on it throws NSCocoaErrorDomain 512 with NSFileProviderInternalErrorDomain underneath. The account's iCloud Drive root answers ubiquitous and Current; the query returns nothing for it either |
| Cancel | No API. An evict issued while `isDownloading` was true was ignored for 30 s; an evict after the download completed worked in 1 s. Cancelling an in-flight download could not be shown |
| Retry after an evict | `startDownloadingUbiquitousItem` returned without error, then the status stayed `NotDownloaded` with `isDownloading` false and no error for the full 120 s: a silent stall, which the app's 30 s stall timeout turns into the failed state. Whether a later start recovers was not seen |
| Offline, a provoked failure | NOT tested (needs the network or a system setting changed) |
| What counts as a failure (PRD open question 1) | Not decided here |
