# Playaway on iPad: design

Written 2026-10-17. A design, not a build. Where it leans on the Human Interface Guidelines it says which rule; where it describes what Apple's own apps do from memory, the claim is marked [unverified].

Starting point, from the code: the iPhone app is iPhone-only (`TARGETED_DEVICE_FAMILY: "1"`), portrait-only, a `NavigationStack` of Playlists then Playlist (a UIKit song table), a floating controller at the bottom, and the player card as a UIKit page sheet sized to its content with the lyrics section below the controls. All of that is reused here; the iPad adds the arrangement, not new parts.

## The one decision: columns by size class, not movable panels

The brief says "panels arranged in different ways". The HIG's answer for iPad is that the *system* arranges them, by the window's size class, and the person's only arrangement choices are the ones every iPad app offers: show or hide the sidebar, and resize the window (Split View, Slide Over, Stage Manager). A player with user-draggable panel layouts would be a tiling window manager inside an app: more to learn, more to test, and nothing the HIG or Apple's own Music app does [unverified for Music's current version]. So: one `NavigationSplitView` whose three columns are Playlists, Songs and Now Playing, and the window's width decides how many of them are on screen at once. Orientation changes are just width changes.

The pieces, and what each is today:

| Piece | Today (iPhone) | On iPad |
|---|---|---|
| Playlists | `PlaylistsView`, a `List` with cloud icons and the Experiments button | The sidebar column (`.sidebar` list style), same rows, same actions |
| Songs | `PlaylistView` with `SongTable` (UITableView) | The content column, same table, same header (name, count, play, Add Songs) |
| Now Playing | The player card (a sheet): handle, artwork, title, scrubber, controls, lyrics section | The detail column, always present in regular width: the card's column without the sheet and without the handle |
| Controller | `FloatingController`, bottom of every screen | Only in compact width, as today; in regular width the detail column is the controller |
| Lyrics | `LyricsPanel` with its disclosure header | The same view inside Now Playing; in a wide window it gets the right half of the column |

## Layouts

Widths below are points; the thresholds are the system's size classes plus one threshold of our own for the lyrics split.

### Regular width, wide (13-inch landscape, 11-inch landscape, Stage Manager wide windows): three columns

```
+------------+---------------------------+--------------------------------+
| Playlists  | Dinner            ▶  Add  |                                |
|            |---------------------------|   +----------+   The words    |
| ● Dinner   | 1  Song one          ☁    |   | artwork  |   scroll here, |
|   Party    | 2  Song two          ☁    |   |          |   the current  |
|   Walks    | 3  Song three  🔊    ☁    |   +----------+   line bold,   |
|            | 4  Song four         ☁    |   Song three    tap seeks.    |
|   ⚗ Exp.   |                           |   Artist · Album               |
|            |                           |   ──────●────────   1:12 / 3:40|
|            |                           |      ⏮   ⏯   ⏭   🔀 🔁         |
+------------+---------------------------+--------------------------------+
```

- Sidebar 260 pt (system default), content flexible, detail at least 360 pt.
- Inside the detail column, when it is 600 pt or wider, artwork + title + scrubber + controls sit in a left sub-column and the lyrics take the right; narrower, the lyrics go below the controls as on the phone. Both are the same `LyricsPanel`; the disclosure header stays, so the words can be folded away and the artwork grows into the space.
- The owner's rule carries over: the controls never move. In the detail column they are pinned to the bottom of the left sub-column (or above the lyrics in the stacked form), and artwork resizing happens above them.

### Regular width, narrower (portrait on any iPad, Split View two-thirds, Stage Manager medium windows): two columns

```
+---------------------------+--------------------------------+
| ☰  Dinner          ▶  Add |   +----------+                 |
|---------------------------|   | artwork  |                 |
| 1  Song one          ☁    |   +----------+                 |
| 2  Song two          ☁    |   Song three                   |
| 3  Song three  🔊    ☁    |   ──────●──────  1:12 / 3:40   |
| 4  Song four         ☁    |      ⏮   ⏯   ⏭                 |
|                           |   ▸ Lyrics                     |
|                           |   (words below when open)      |
+---------------------------+--------------------------------+
```

- The sidebar is hidden and slides over on the ☰ button, which `NavigationSplitView` provides. Choosing a playlist dismisses it. This is the HIG's prescribed behaviour for a sidebar in portrait, not a custom one.
- Songs and Now Playing share the width roughly 50/50, detail never under 360 pt.

### Compact width (Split View one-third, Slide Over, and iPhone): the stack

Exactly the iPhone app: Playlists pushes Playlist, the floating controller sits at the bottom, tapping it opens the card. `NavigationSplitView` collapses to a stack on its own in compact width, so this is not a second implementation; it is the same view tree with the detail presented as the card. The card stays a sheet only in compact width; in regular width a sheet would appear as a centred form sheet, which is wrong for a player, so the sheet path is never used there.

### Multitasking and Stage Manager

A window can move between all three forms while running (drag the divider, rotate, resize a stage). Nothing is torn down: the split view re-lays the same columns, the engine keeps playing, the table keeps its scroll position, the lyrics keep their place. The one thing to get right is state ownership: the selected playlist and the open song live in `AppModel` (they do today, as `path` and the active session), not in a column's view, so a column that disappears and comes back shows the same thing.

### External display

Nothing special in v1. A mirrored or extended display with Stage Manager is just another regular-width window.

## Behaviour that is new on iPad

- **Selection, not navigation.** In regular width, tapping a playlist selects it (the sidebar row highlights, the songs column changes) rather than pushing a screen. Tapping a song plays it, as today, and the detail column updates; it does not navigate anywhere. The `path: [URL]` array becomes the sidebar's selection in regular width; in compact width it is still the stack.
- **Now Playing when nothing is playing.** The detail column shows an empty state: the app's symbol, "Nothing playing", and "Choose a song" in secondary text. Not a blank column.
- **Keyboard.** Space play/pause, left/right arrows seek 5 s, up/down arrows previous/next, ⌘N new playlist, ⌘O Add Songs, ⌘L show/hide lyrics, ⌘⌥S toggle sidebar (the system's). Declared with `.keyboardShortcut` and listed in the system's shortcut overlay (hold ⌘), so they are discoverable without a help screen.
- **Pointer.** Hover effects on rows and buttons come free from the system components; the scrubber gets a pointer-friendly larger hit area through `.hoverEffect` [the modifier's exact behaviour on a `Slider` is unverified].
- **Drag and drop.** Dropping audio files from Files onto the songs column adds them (the same intake flow as Add Songs, so the iCloud question is asked the same way). Dragging a song row onto a playlist in the sidebar adds it there. Both are `.dropDestination` on views that already exist.
- **Orientation.** All four orientations on iPad; the iPhone stays portrait-only as today.
- **Dynamic Type.** The three-column form is allowed to drop to two columns at accessibility text sizes, because 13-inch at the largest sizes cannot hold three readable columns; the split view's `columnVisibility` is set from the size class and the type size together.

## What does not change

- Playback, playlists, iCloud, lyrics generation, the audio lease: all in the shared core or in `AppModel`; no iPad code touches them.
- The player card on the phone: untouched, including the stepped resize and the controls-never-move rule.
- No tab bar (three top-level destinations are not peers; it is one hierarchy), no toolbar duplicates of sidebar actions, no floating panels, no custom gestures to rearrange columns.

## How it maps to code

- `RootView`: `NavigationSplitView(columnVisibility:) { PlaylistsView } content: { PlaylistView(selected) } detail: { NowPlayingColumn }`, with the current `NavigationStack` kept for compact width through the split view's own collapsing. One file changes; `PlaylistsView` and `PlaylistView` gain a selection binding and lose nothing.
- `NowPlayingColumn`: the body of `PlayerCard` factored into `PlayerColumn(layout: .stacked | .sideBySide)`, used by the card (stacked, with handle) and by the detail column (either, no handle). `LyricsPanel` unchanged.
- `PlayerChrome`: the floating controller and the sheet are shown only when `horizontalSizeClass == .compact`.
- `project.yml`: `TARGETED_DEVICE_FAMILY: "1,2"`, iPad orientations all four, iPhone portrait; `UIApplicationSupportsMultipleScenes` left off in v1 (one window) unless Stage Manager multi-window is wanted, which is a separate decision.
- Tests: `scripts/ios-ui-tests.sh` gains an iPad device option; the UI tests that open the card get a regular-width variant that asserts the detail column instead; new tests: three columns at 13-inch landscape, two in portrait, the stack in a one-third Split View, selection survives a width change while playing, keyboard shortcuts, drop of a file onto the songs column. The pixel helpers that prove "controls never move" are reused on the detail column.

## Honest costs

- The iPhone app has had every change proven on one portrait layout; the iPad adds three forms and live transitions between them. Expect most of the work to be in tests and in state ownership, not in drawing.
- The sheet-based card does not exist in regular width, so the lyrics collapse, the progress display and the "open in Playaway" ideas all need their detail-column form checked, not assumed.
- Split View one-third is 320 pt wide on some iPads [unverified exact figure]: the compact stack must already work at that width on the phone, and the song table's cloud icons and the card's scrubber have only been seen at iPhone widths.
- Multi-window (two playlists in two windows) is tempting on iPad and is deliberately out: one engine, one active session, one lease; two windows would need a rule for which one owns playback.

## Order of work

1. `project.yml` device family and orientations; run the existing UI suite on an iPad simulator in compact Split View width (nothing new yet, finds what breaks at 320 pt).
2. `NavigationSplitView` with selection, the detail column as the stacked player column, empty state. Tests: three forms, selection survives resizing.
3. Side-by-side lyrics in a wide detail column; keyboard shortcuts; drop targets.
4. Pointer polish, accessibility sizes, Stage Manager pass on a real iPad.

Each step ships; step 1 alone is a day and answers whether the compact stack is already iPad-ready.
