# PRD

The app's first window is on screen within 1 second of opening it on an M2 MacBook Air.

## Problem

Music (formerly iTunes) takes a long time to open and often shows a loading state before the person can do anything. Someone who just wants to hear their music has to wait, and the wait makes the whole app feel heavy. Apple Notes is the person's benchmark for how an app should feel: it opens and they can work straight away. A player that is slow to appear loses the very reason the person chose a simple player in the first place.

## Solution

The app's first window is on screen within 1 second of opening it on an M2 MacBook Air. That window is a playlist window: the playlist windows the person had open last time, or a fresh untitled playlist when there is nothing to bring back. The person can start choosing and playing music as soon as they see the window, with no splash screen, no loading indicator and no waiting for background work such as checking for updates or finding out whether every audio file in a playlist is still where it was. This removes the wait described above and makes the app feel as immediate as Apple Notes.

## User Experience

## Golden path
1. The person opens the app from the Dock, Spotlight, Finder or Launchpad.
2. Within 1 second a playlist window is on screen and ready to use. If the person had playlist windows open when they last quit, those windows come back; otherwise a new untitled playlist window appears (this is a proposal; see open questions).
3. The person plays a playlist, adds files or opens a file and music starts, with nothing else to wait for.

## Alternate flows
- **Opening a playlist or audio file from Finder:** the app opens and does what that story describes. The speed target here is about the first window and does not set a separate target for playback.
- **App already running:** bringing the app to the front shows its windows at once.
- **First time opening the app:** the person sees the same kind of playlist window, with no welcome tour or setup step.
- **A playlist that had many tracks:** its window still appears at the same speed. Whether each track's audio file is still where it was is worked out after the window is visible, so a track may take a moment longer to show its final state than the window takes to appear.

## Empty and error states
- If the window cannot be shown within the target, nothing is hidden or faked: there is no placeholder window and no progress indicator pretending the app is ready.
- If a playlist the person had open cannot be read, the app still shows a window and does not wait on or block behind it. What that window says is not specified here.
- Background work such as checking for updates happens after the window is visible and never holds it back.

## Structure
- The first thing on screen is an ordinary Mac document window for a playlist. Its title bar shows the playlist's name, or Untitled for a new playlist.
- Inside the window are the playlist's tracks, in their order, together with the playback controls described by the other stories. The exact list of elements is decided in the on-screen-simplicity story and is not decided here.
- Each playlist has its own window. There is no single main window and no list of all playlists.
- No splash screen, no loading bar and no first-run wizard appear before or on top of it.

## Behaviour
- The first window appears at the same speed whether the person has restored one window or several. The number of windows and tracks that must be supported at this speed is not decided yet.
- Anything that is not needed to show the window is deferred until after it appears.

## Explicit non-behaviours
- Does not show a splash screen or loading indicator.
- Does not wait for an update check before showing the window.
- Does not wait to confirm that every audio file in a playlist still exists before showing the window.
- Does not set a target for how quickly playback begins after pressing play. That is an open question below.
- Does not decide whether the 1 second target applies to a cold launch (after restarting the Mac) or a warm launch (app used recently). That is an open question below.

## First window within 1 second

> Anchor: `prd.launch.window`

WHEN the person opens the app on an M2 MacBook Air THE SYSTEM SHALL show its first window within 1 second of the open action.

## Acceptance criteria

A non-technical person can check the requirement above as follows.

1. On an M2 MacBook Air running macOS 26, quit the app, then open it from the Dock while timing from the click.
2. PASS: the first window is fully on screen at or before 1 second. FAIL: it appears after 1 second, or a splash screen, loading indicator or placeholder is shown first.
3. Repeat 10 times. PASS requires all 10 runs to meet 1 second. Any single run over 1 second is a FAIL.
4. Repeat steps 1 to 3 after restarting the Mac, and report that result separately from the earlier one. Which of the two the 1 second target formally applies to is an open question (see Open questions), so both results are reported and neither is hidden.
5. With an update available, repeat step 1 and check that the window still appears within 1 second and the update prompt, if any, appears afterwards.

## Open questions

These are unresolved. They are recorded here so nobody invents an answer.

1. **Cold or warm launch.** The 1 second target does not yet say whether it applies after a restart of the Mac (cold) or when the app has been used recently (warm). The person has observed that Apple Notes takes about 1 second longer cold than warm, so the answer decides how hard the target is. Until it is decided the requirement above is stated without choosing, and both measurements will be reported separately.
2. **Time from pressing play to first sound.** The person wants the app to be very responsive to play, but no number has been chosen. Not a requirement of this story.
3. **How much must be supported.** How many restored playlist windows, and how many tracks in each, the first window must handle within the 1 second target is not decided.
4. **Other benchmark apps.** The person mentioned Apple Notes. A second benchmark app may have been intended but is not recorded and is not a requirement.
5. **What appears on a launch with nothing to restore.** This story proposes a new untitled playlist window, the usual behaviour of document apps. It is a proposal pending the owner's decision.
6. **Which window hosts a single audio file opened on its own.** Owned by the story about playing a file from Finder; recorded here only because it decides what the first window is when the app is opened by a file.

## Constraints

- The 1 second target is measured on an M2 MacBook Air running macOS 26 or later.
- The app is distributed as a signed, notarized download outside the Mac App Store, and updates are delivered by an automatic update mechanism. That mechanism must not slow the appearance of the first window; the update story owns that mechanism and this story only checks the ordering.
- The measurement start point and stop point must be defined and repeatable so a result can be compared between releases.
- Each playlist is its own document with its own window; there is no single main window.

## Out of scope

- A target for the time from pressing play to first sound.
- Choosing between cold and warm launch (open question 1).
- Performance on other Mac models.
- Performance targets for many restored windows or very large playlists.
- Playlist and playback behaviour themselves (separate stories).
- How and when the update mechanism starts (separate update story).

