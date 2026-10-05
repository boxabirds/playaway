# UI/UX Improvements

**Status:** the macOS redesign in part 1 was built (see `spec/stories/007-see-only-what-i-need-on-screen/prd.md`, "Emphasis follows use"). Two details differ from the mockups: Shuffle and Repeat use the system's filled toggle look while on, and Remove is a quiet icon at the footer's right edge. The iPhone section is a proposal; the technical design is in `IPHONE-TECH-DESIGN.md`.

Mockups for everything below are in [`ui-mockups.html`](ui-mockups.html) (open in a browser). The "before" image is a screenshot of the real app, [`ui-current.png`](ui-current.png), taken with a 5-track playlist playing track 2. The proposal is a design, not an implementation: nothing in `Sources/` has changed.

## Summary

Reviewed: the playlist window of LocalPlayer on macOS (`TransportControlsView`, `PlayModeControls`, `PlaylistWindowController`), against specs 007, 008 and 011 and the element list in `Resources/ui-manifest.json`.

The window follows the spec's three groups, and every element is standard, labelled and accessible. What it lacks is hierarchy. Everything is the same size and the same blue, so the eye has nowhere to land:

- **Play/Pause is the same size and weight as Stop, Previous and Next.** It is the one control used all the time.
- **Volume has a full row and the same look as the seek bar.** Seek matters during playback. Volume is set once.
- **Shuffle and Repeat are word buttons** ("Shuffle: Off") the same size as the transport. They are set once per session.
- **Nothing in the list shows which track is playing.** The only clue is a file name in the header.
- **Five stacked rows of controls** (title, buttons, seek, volume, modes) sit above the list, which is what the window is for.

The proposal keeps every current control and every current job. It changes size, colour, position and grouping. It also adds three small elements: a playing marker in the list, "Track 2 of 5", and a track count. Each needs a manifest entry (see Spec impact).

I have not measured the height saved in points. The controls drop from five rows to three, and the freed height goes to the list.

## Critical Issues

### Issue: No visual hierarchy in the playback controls
**Current State**: Previous, Pause, Stop and Next are four identical small bezel buttons, left-aligned. Seek and volume sliders are the same blue and thickness. Shuffle and Repeat have the same size and bezel as the transport. Accent blue is on every control.
**Problem**: Everything shouts equally, so nothing does. The most frequent action (Play/Pause) must be found among its neighbours. Stop sits next to Next and has the same weight, though it is rarely used.
**Recommendation**: Give each element a size and colour by how often it is used:
1. **Play/Pause**: a 56 pt filled accent circle, the only filled accent shape in the window.
2. **Track title**: 24 pt bold, up from 15 pt semibold.
3. **Previous and Next**: 40 pt targets, label colour (not accent), flanking Play.
4. **Seek bar**: 4 pt thin accent fill; times in 11 pt tertiary grey beneath it.
5. **Shuffle and Repeat**: icon-only, secondary grey, and the accent plus a soft pill only while on.
6. **Volume**: small slider, grey fill, right side of the control row.
7. **Stop**: small tertiary icon at the top right, beside the track title it ends.
**Impact**: One clear target for the common action; rare controls stop competing with it.
**Implementation Notes**: Play stays a standard `NSButton` (system prominent or glass style at the largest control size), not custom drawing, to stay inside spec 008. The exact API is unverified; check against current AppKit and the HIG before building. Restyling is the main work; the actions and view-model calls are unchanged.

### Issue: The playing row is not marked
**Current State**: In the track list, the playing row looks like any other. The stripe pattern and the selection highlight make it worse.
**Problem**: A person scanning the list cannot tell what is playing or where they are. After removing or reordering rows, nothing confirms what is current.
**Recommendation**: In the existing leading 16 pt slot (the one the hazard icon uses), show an animated waveform or speaker glyph for the playing row, with accent-coloured semibold text. Show a pause glyph while paused. Keep the standard blue highlight for selection, so "selected" and "playing" are different states. Marker and weight carry the meaning, so colour is not the only signal.
**Impact**: At a glance, the person sees which track is current and what is selected.
**Implementation Notes**: One more state for `TrackCellView`. The hazard icon and the playing marker can never show at once, because a track that cannot be played is not playing.

## High Priority Improvements

### Issue: Transport buttons are left-aligned
**Current State**: The code comment says the buttons are centred ("the usual player layout") and adds a `centerXAnchor` constraint. In the real screenshot they sit at the left edge.
**Problem**: Transport controls in every mainstream player are centred under the title. Left-aligned they look unplaced.
**Recommendation**: Centre the Previous/Play/Next cluster in the window. In the mockup, a three-column grid (modes, transport, volume) keeps Play exactly centred.
**Impact**: Layout reads as designed.
**Implementation Notes**: Likely the constraint is overridden by the stack's `.leading` alignment. I did not debug why.

### Issue: Volume and Mute take a whole row
**Current State**: A mute button and a 140 pt slider on their own row between the seek bar and the mode buttons.
**Problem**: Volume is adjusted rarely but costs a full row of height. It looks as important as seek.
**Recommendation**: Put it in the control row on the right: a small speaker button (click to mute) and a short grey slider about 70 to 90 pt wide. The speaker glyph changes to the slashed form when muted, as it does now.
**Impact**: Frees a row for the list and lowers volume's visual weight.
**Implementation Notes**: Same view-model calls (`toggleMute`, `setVolume`).

### Issue: Shuffle and Repeat are verbose and hard to read as state
**Current State**: Buttons titled "Shuffle: Off" and "Repeat: Off", with an on/off bezel that looks almost the same in both states.
**Problem**: The person has to read the words to know the state. Two wide buttons take a whole row.
**Recommendation**: Icon-only toggles in the control row's left zone. Off: secondary grey, no background. On: accent colour with a soft rounded background. Repeat one: accent plus the "1" form of the glyph. Tooltip and accessibility value keep the words ("Repeat: One").
**Impact**: State is visible by shape and colour together, and the row is freed.
**Implementation Notes**: The accessibility value is already set. The "1" badge must stay: without it, Repeat all and Repeat one differ by nothing visible.

### Issue: Controls take too much of the window
**Current State**: Five stacked rows above the list. The list has a bezel border, striped rows that continue into empty space, and a bottom bar of two buttons.
**Problem**: The list is the largest and most-used part of the window and gets what is left.
**Recommendation**: Three rows (title block, seek bar, control row). Remove the list border and stripes. Replace the bottom buttons with a slim footer: "+ Add Files" on the left, "5 tracks" in secondary grey, and Remove only when rows are selected.
**Impact**: More rows visible in the same window; no ghost rows.
**Implementation Notes**: `usesAlternatingRowBackgroundColors = false`, and drop the bezel border on the scroll view.

## Medium Priority Enhancements

### Issue: File names are shown as titles, extension included
**Current State**: The header and the list show "track2.mp3".
**Problem**: The extension is noise in the largest text on screen.
**Recommendation**: Show the name without its extension. Keep the full file name as the tooltip.
**Impact**: Cleaner title and list.
**Implementation Notes**: Display only. The AppleScript `current track` value should stay as it is, so decide whether UI and script strings may differ. Existing tests assert the visible name.

### Issue: "Track 2 of 5" is missing
**Current State**: The header shows only the name.
**Problem**: No sense of place in the playlist.
**Recommendation**: A 12 pt secondary line under the title.
**Impact**: Orientation, especially with shuffle on.
**Implementation Notes**: New element, needs a manifest entry (job: play a playlist).

### Issue: Remove looks permanently disabled
**Current State**: A pale "Remove" button next to "Add Files" that is disabled until a selection exists.
**Problem**: It reads as dead UI at all other times.
**Recommendation**: Show Remove in the footer only while rows are selected, or keep it as a small icon button. Delete and Backspace keep working either way.
**Impact**: Less visual clutter.
**Implementation Notes**: Spec 007 allows "shown disabled or not shown".

## Low Priority Suggestions

- **Optional compact mode.** Let the window shrink to the header alone (no list) for people who just want a mini player. This is new functionality, so it needs its own story.
- **Window title.** A playlist created and edited through a script showed "S — Edited" in the title bar. I did not investigate it; it may only affect autosaved documents that were never saved by hand.
- **Track durations in the list.** Would help, but need reading each file, which is new work.

## Positive Observations

- The spec-driven rule that every element serves one of three jobs (and the manifest check) is working: nothing extraneous is on screen.
- All controls have accessibility identifiers, labels and values; icon-only buttons are labelled.
- The elapsed and remaining times use monospaced digits, so they do not jitter.
- Previous and Next are disabled when they cannot do anything, as the spec says.
- Native controls and system symbols, so the window follows light and dark appearance.

## Spec impact (needs the owner's decision before any of this is built)

1. **Spec 007, Structure.** It says three groups top to bottom, with Shuffle and Repeat as the second group. In the proposal they sit in the control row with the transport. Each element still maps to its own job in the manifest (Shuffle and Repeat stay "play a playlist"), but the sentence about groups would need rewording.
2. **Spec 008, standard controls only.** A large prominent Play button must stay a standard button style. Verify that before committing to it.
3. **Manifest.** New elements need entries in `Resources/ui-manifest.json`: the playing marker, "Track N of M", the track count. The check fails on any element without one, which is the point of the check.
4. **Stop placement is a judgement call.** I put it at the top right of the title block, because it ends "this track" rather than navigating. The alternatives are beside Next (looks like part of volume or navigation) or in a menu only. Spec 011 requires Stop, so it should not be removed.
5. **Automation parity.** No AppleScript command is added or removed, and the actions behind each control are unchanged. Tests that check visible strings (`nothingPlayingText`, file names) and the manifest will need updating, and any new visible state (playing marker) needs a test through the UI route and, where it has a script equivalent, the script route.
6. **Window size.** The control row needs about 380 pt of width. The current minimum width is 420 pt, so it fits.

## iPhone version (proposal)

Nothing in the specs covers iOS today (the package targets macOS 26 only). This section is a design proposal, not a plan. See the three phone mockups in `ui-mockups.html`.

### Structure

1. **Playlists** (home): large title, one row per playlist with name and track count. "+" creates one. The playing playlist is marked. A playlist with missing files shows "1 missing" in the row.
2. **One playlist**: large title, then two wide buttons, a filled **Play** and a tinted **Shuffle**. Tapping a row plays it (iOS has no double-click). Swipe a row to remove it; Edit mode reorders. Add files from the "+" in the navigation bar.
3. **Mini player**: docked above the home indicator on screens 1 and 2: playing marker, title, Pause, Next, and a 2 pt progress line. Tapping it opens Now Playing.
4. **Now Playing sheet**: a large title, "Track 2 of 5 · Morning", a seek bar with a 28 pt touch height, the 76 pt filled Play circle flanked by 56 pt Previous and Next, and Shuffle and Repeat as 48 pt icon toggles underneath. Drag down to dismiss.

The same hierarchy rules apply as on the Mac: one dominant Play, medium Previous and Next, quiet modes.

### Differences from the Mac app, with reasons

- **No Stop button.** iOS players use Pause, with a swipe-to-dismiss mini player to end. Spec 011 requires Stop on the Mac; for iOS it is a decision.
- **No in-app volume slider.** The hardware buttons and Control Center are the control. The Mac spec's rule that the app's own level is separate from the system volume cannot hold on iOS.
- **Lock screen and Control Center controls.** An iOS player is expected to have them, plus background audio. These need now-playing info and remote-command support and the audio background mode.
- **Automation parity.** The AppleScript API has no iOS counterpart. The equivalent is App Intents (Shortcuts and Siri). This follows the project rule that UI and automation stay in step, and would need its own spec.
- **Files and "missing" tracks.** An iOS app cannot read arbitrary paths. Tracks have to come from the document picker with security-scoped bookmarks. Story 005 (missing files) would need rethinking: "Locate" becomes re-picking a file, and files in iCloud that are not downloaded are a new state.
- **Documents.** `PlaylistDocument` is an `NSDocument`; on iOS it would be a `UIDocument`. The `.lplaylist` format stays the same, so playlists could open on both.
- **iPad.** Reuse the Mac layout: a sidebar of playlists next to the list, with the control block on top.

### What is likely reusable, and what is not

I did not build or test any of this. From reading the code: the pure logic (`AdvanceDecider`, `ShuffleOrder`, the playlist model, the store) imports only Foundation or Combine and would probably carry over. The AppKit views, `NSDocument`, scripting and Sparkle updates would not. The playback engine would need an audio-session setup that macOS does not have.

### Accessibility and touch

- Every control is at least 44 pt; the seek bar has a 28 pt-tall touch area, with a larger drag target.
- Dynamic Type for titles and rows; the Now Playing layout must survive the largest sizes.
- VoiceOver: the seek bar is an adjustable element announcing "1 minute 12 of 3 minutes"; the playing marker is spoken ("playing").
- Haptic tick on Shuffle and Repeat toggles; nothing animates under Reduce Motion.
