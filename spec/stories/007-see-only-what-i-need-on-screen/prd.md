# PRD

Every visible element of the main window serves one of three jobs, and a recorded element-to-job mapping is enforced by a test.

## Problem

Music players accumulate controls, panes and information because each addition seems useful on its own. Every extra item costs the person attention, and a person who only wants to play files and keep a few playlists has to look past all of it. Interfaces produced quickly, including those drafted by AI tools, are especially prone to packing in extra items 'just in case'. 'No extraneous information' is easy to promise and impossible to check unless it is written down in a way that someone can verify.

## Solution

After this is built, a person opening a playlist window can play a file, play a playlist with repeat and shuffle, and manage that playlist without looking past anything unrelated, and can point at any item on screen and say which of those three jobs it serves. Each visible element is recorded next to the job it serves. An element that serves none of the three jobs does not appear. A check run on every build fails when a playlist window shows something that is not on that record, so extra items cannot creep in unnoticed. This resolves the problem that simplicity was a promise nobody could check.

## User Experience

## Golden path
1. The person double-clicks a playlist file, or chooses New Playlist. One playlist window opens. There is no main window and no list of playlists; each playlist has its own window.
2. The window shows three areas from top to bottom. The top area shows the current track's name, its place in the playlist (for example "Track 2 of 5"), Stop, the seek bar with elapsed and remaining time, and one row of controls: Shuffle and Repeat on the left, Previous, Play/Pause and Next in the centre, and volume on the right. Below it is the track list, then a slim footer with Add Files, the track count and Remove. The person can name the job of every item they see: play a file, play a playlist with repeat and shuffle, or manage that playlist.
3. The person presses play in the first group, or chooses a track in the third group. The first group updates to show that track playing. Nothing else on screen changes or competes for attention.
4. The person drags files into the track list or reorders rows. The list updates in place and no other part of the window changes.

## Alternate flows
- **Window states:** the same rule applies in a new untitled playlist, while something is playing, while the playlist is being edited and while a message is shown.

## Empty states
A new untitled playlist with nothing playing shows only the items needed to start one of the three jobs: the playback controls, the shuffle and repeat controls, and an empty track list with a way to add files. It does not fill the space with tips, promotions or placeholder panels.

## Error states
- **Unsupported file:** when the person adds or opens a file whose type is not supported, a short message names the problem (for example 'This file type is not supported yet') and offers one Dismiss button. The message relates to the job in progress. The window behind it is unchanged. Dismissing it returns the person to the window exactly as it was.
- **Nothing else appears:** an error never adds a permanent item to the window. After dismissal the window contains only recorded items again.

## Structure
A playlist window has three areas and nothing else: the now-playing area, the track list and the footer. Each item belongs to exactly one job in the manifest, and the area an item sits in does not have to match its job. Play a file: the track name, Previous, Play/Pause, Next, Stop, the seek bar with its times, volume and Mute. Play a playlist: Shuffle, Repeat and the "Track N of M" line. Manage playlists: the track list, Add Files, Remove, the track count and the empty-list hint. Creating, opening, renaming and saving a playlist are standard document and menu actions rather than items in the window. There is no fourth area: no sidebar of unrelated sections, no footer of statistics, no promotional or tips panel. Every item is one that its job uses.

## Emphasis follows use

> Anchor: `prd.simple.hierarchy`

The items used most are the largest and boldest, and the items used least are the quietest. Play/Pause is the largest control and is always filled with the accent colour. Shuffle and Repeat are filled with it only while on, using the system's own toggle look, so their state is shown by shape as well as colour. The track name is the largest text. Previous and Next are medium. Shuffle, Repeat, volume, Stop and the times are small and grey while off. Which row is playing is shown in the track list by a marker and a bolder name, so it is not shown by colour alone, and it looks different from a selected row.

WHILE a window is shown THE SYSTEM SHALL draw Play/Pause larger than every other control, and SHALL draw Shuffle, Repeat, Stop and volume with less emphasis than Previous and Next.
WHILE a track of the playlist is playing or paused THE SYSTEM SHALL mark that row in the track list with a playing or paused marker.

## Behaviour
- Adding a new visible element requires recording which job it serves.
- Removing the record for an element, or the job it serves, makes the check fail.
- An item that is not usable in the current state is either shown disabled where the person expects it, or not shown, but never replaced by unrelated content.

## Explicit non-behaviours
- No element is shown 'because it might be useful'.
- No element serves a job outside the three listed.
- The window does not show decorative or statistical information that serves none of the three jobs.
- There is no main window and no list of playlists.

## Open
Which window plays a single audio file opened on its own is not decided (see Open questions). If it has its own window, that window needs its own record.

## Acceptance criteria

A product owner can verify each of these by using the app, reading one list and watching a short demonstration, without reading any code.
1. Open the list of window items. Every line names one item and one of the three jobs: play a file, play a playlist, manage playlists. No line is blank or names anything else.
2. Create a new untitled playlist with nothing playing. Point at each visible item in its window: it is on the list, and its job is one a person would recognise.
3. Play a file, then play a playlist, then start editing a playlist, then trigger a message (add an unsupported file). In each of these states, every visible item in the playlist window is on the list.
4. Ask a first-time user to name the job of each visible item. They can name a job for every one, with no 'what is this for?' answers.
5. Ask the team to demonstrate the check with one extra visible item that is not on the list. The check reports a failure and names that item.
6. Ask the team to demonstrate the check with one item's line removed from the list. The check reports a failure and names that item.
7. Ask the team to run the check on the real app and list together. It reports success with no failures named.
8. Play a playlist and look at the window for three seconds without reading it. Play/Pause is the first thing the eye lands on. Stop, volume, Shuffle and Repeat are visibly quieter than Previous and Next.
9. With a playlist playing, the playing row is marked and a different row is selected: the two look different. Pause: the marker changes to a paused one.

## Every visible element serves a job

> Anchor: `prd.simple.mapping`

THE SYSTEM SHALL show in a playlist window only elements that are recorded as serving one of three jobs: play a file, play a playlist, or manage playlists.

## Unrecorded elements are rejected

> Anchor: `prd.simple.unmapped`

IF a playlist window shows an element that has no recorded job THEN THE SYSTEM SHALL NOT pass the build check.

## Records match what is on screen

> Anchor: `prd.simple.stale`

IF a recorded element is not present in a playlist window in any of its states THEN THE SYSTEM SHALL NOT pass the build check.

## The rule holds in every window state

> Anchor: `prd.simple.states`

WHILE a playlist window is in any of its states (new untitled playlist, playing, editing the playlist, showing a message) THE SYSTEM SHALL show only recorded elements.

## Constraints

- Runs on macOS 26 and later.
- The check must run on every build and must not need a person to look at the screen.
- The check must fail clearly, naming the unrecorded element, so the cause is obvious.
- The record is the only place that decides which jobs exist: play a file, play a playlist with repeat and shuffle, manage playlists.

## Open questions

These are not decided and are deliberately not answered here.
1. The actual list of elements in a playlist window, each tied to a job. The list is `Resources/ui-manifest.json`; the three areas above are the structure.
2. Whether v1 explicitly refuses features such as an equalizer, lyrics, ratings or an album-art browser. People will ask for them; no decision has been made.
3. What counts as an element for the check: controls only, or also labels, icons and artwork.
4. Whether menus and dialogs fall under the same rule as the playlist window.
5. Which window plays a single audio file that is opened on its own. If it has its own window, that window needs its own record of elements; if it uses a playlist window, no second record is needed.

## Out of scope

- Choosing the actual list of elements.
- Visual styling, the look of the glass effects and compliance with Apple's design guidelines (separate story).
- Accessibility behaviour such as VoiceOver and keyboard use (undecided, tracked as an open question in the product requirements).
- Judging whether a recorded job assignment is sensible; the check only verifies that a record exists and matches the screen.
- Any window other than a playlist window, including a window for single-file playback if one is decided later.
- Creating, opening, renaming, saving and deleting playlists as document actions (separate stories). Deleting a playlist is not an app feature; the person does it in Finder.

