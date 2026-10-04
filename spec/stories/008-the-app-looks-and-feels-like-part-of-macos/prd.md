# PRD

The app uses standard macOS controls, follows system appearance and accessibility settings, uses system Liquid Glass, and is reviewed against Apple's Human Interface Guidelines.

## Problem

Music players that feel foreign on a Mac are tiring to use. Custom-drawn windows, unfamiliar buttons and menus that do not behave like other Mac apps force the person to relearn basic things, and they look dated or amateur next to Apple's own apps. People who dislike iTunes for being bloated, and dislike other players for being geeky, also tend to notice and care when an app looks careless. Without a clear, checkable standard for 'looks and feels native', a new app drifts toward generic, over-decorated or inconsistent design.

## Solution

The app looks and behaves like it belongs on macOS 26. It uses the standard windows, menus, buttons and controls the Mac provides, follows the person's light or dark appearance, and respects their system accessibility settings instead of overriding them. Where it uses Liquid Glass, it uses the real macOS material rather than an imitation. Each release is checked against Apple's Human Interface Guidelines using a written checklist, so 'native' is something that can be verified rather than a feeling. This resolves the foreign-feeling, inconsistent and unverifiable design described above. Which exact surfaces get Liquid Glass is not yet decided and is listed under open questions.

## User Experience

## Golden path
1. The person opens the app on a Mac running macOS 26 or later.
2. A playlist opens in its own window. The window, menu bar and controls look and behave like those in Apple's own apps. Buttons, sliders and menus are the familiar ones.
3. If the Mac is in dark appearance, the app is dark. If it is in light appearance, the app is light. If the person switches while the app is open, the app switches immediately without needing to be restarted.
4. Where the app uses Liquid Glass, it looks and behaves like the glass in Apple's own apps.

## Alternate flows
- **System accessibility settings are on** (for example Increase Contrast, Reduce Transparency or Reduce Motion): the app does not fight the setting and never turns it off or works around it. What the app looks like in each such setting is not yet specified; see open questions.
- **Mac runs an older macOS than 26:** the app is not supported. Older versions are not offered the app.
- **A review item fails before a release:** the failure is recorded and either fixed or explicitly accepted as an exception; it is not silently ignored.

## Empty and error states
- Empty state: with nothing playing, a playlist window still uses standard controls and appearance; there is no special blank design in this story.
- Error state: there is no user-visible error state in this story. Review failures are an internal release matter.

## Structure
Each playlist is a document that opens in its own window. There is no main window and no separate window that lists playlists. The menu bar has the standard macOS arrangement: an application menu with About and Quit, a File menu, a Window menu and a Help menu, using the standard names and keyboard shortcuts. The File menu holds the standard document commands (New Playlist, Open, Open Recent, Close, Save and Rename) together with the command that opens an audio file. The exact menu names of the playlist Open and the audio-file Open are provisional. Whether an Edit menu is also needed for adding and removing tracks is an open question. No custom title bar, custom window buttons or custom-drawn controls replace the system ones.

## Behaviour
- Controls respond the way the same controls do in other Mac apps, including standard keyboard shortcuts for items the app offers.
- Appearance changes apply to every open window at once.

## Explicit non-behaviours
- Does not offer its own light/dark setting that overrides the system.
- Does not turn off or work around a system accessibility setting.
- Does not draw fake glass or imitate system materials.
- Does not use custom-drawn replacements for standard windows, buttons or menus.
- Does not have a main window or a window that lists playlists.
- Does not decide in this story which surfaces use Liquid Glass.

## macOS 26 or later

> Anchor: `prd.look.platform`

THE SYSTEM SHALL require macOS 26 or later and SHALL declare that requirement so that Macs running an earlier version are not offered the app.

## Standard controls and windows

> Anchor: `prd.look.controls`

THE SYSTEM SHALL present its windows, buttons, sliders and menus using the standard controls provided by macOS rather than custom-drawn replacements.

## Standard menu bar

> Anchor: `prd.look.menubar`

THE SYSTEM SHALL provide a standard macOS menu bar containing an application menu with About and Quit, a File menu, a Window menu and a Help menu, using the standard names and standard keyboard shortcuts for every item it offers, and the File menu SHALL contain the standard document commands New Playlist, Open, Open Recent, Close, Save and Rename together with the command that opens an audio file.

## Follow light and dark appearance

> Anchor: `prd.look.appearance`

WHEN the system appearance changes between light and dark, including while the app is running, THE SYSTEM SHALL switch every open window to the new appearance without requiring a restart.

## Respect system accessibility settings

> Anchor: `prd.look.a11y_respect`

IF a system accessibility display setting is turned on THEN THE SYSTEM SHALL NOT turn it off, override it, or provide its own setting that contradicts it.

## Use the system Liquid Glass material

> Anchor: `prd.look.glass`

WHERE the app uses Liquid Glass THE SYSTEM SHALL use the Liquid Glass material provided by macOS and SHALL NOT use a custom-drawn imitation.

## Guidelines review for each release

> Anchor: `prd.look.review`

WHEN a release is prepared THE SYSTEM SHALL be accompanied by a recorded review against a written Human Interface Guidelines checklist in which every item is marked pass, or fail with a recorded exception.

## Acceptance criteria

A non-technical person can verify each of these by using the app on a Mac running macOS 26 or later, without reading any code.
1. Look at the menu bar with a playlist window in front. The titles are the app name, File, Window and Help. The app menu has About and Quit, and Quit works with the usual Command-Q.
2. Open the File menu. It lists New Playlist, Open, Open Recent, Close, Save and Rename, and also a command for opening an audio file.
3. Open two playlists. Each is in its own window. There is no other window that lists playlists.
4. Look at the buttons, sliders and window edges. They look the same as in Apple's own apps, with no custom-drawn buttons or window controls.
5. With a playlist window open, switch the Mac between light and dark appearance in System Settings. The window changes at once, without restarting the app, and the same happens with two windows open.
6. Turn on Reduce Transparency, Increase Contrast or Reduce Motion in System Settings, then open the app. The app opens, and afterwards the setting is still on. The app has no setting of its own for light or dark or for these options.
7. Wherever the app shows a glass effect, it looks like the glass in Apple's own apps on the same Mac.
8. Try to install the app on a Mac running macOS 25 or earlier. It is not offered or does not open.
9. Before a release, a written Human Interface Guidelines checklist exists. Every line is marked pass, or marked fail with a written exception. A release with an unmarked line, or a fail without an exception, is refused.

## Constraints

- Runs on macOS 26 and later only.
- The app must follow Apple's Human Interface Guidelines.
- Every app-specific action must also be reachable by AppleScript. System-standard menu items such as About, Quit, Hide, Services, Window and Help are excluded (covered in the AppleScript story).
- Launch speed targets are covered in the launch-speed story.

## Open questions

These were asked and have not been answered. They are deliberately not decided here and must not be assumed by anyone implementing this story.

1. Which surfaces use Liquid Glass, and which do not.
2. What the app looks like when Reduce Transparency is turned on.
3. What is required for VoiceOver and for use with the keyboard alone. This has been asked three times without an answer.
4. Who signs off that the app 'looks designed by Apple's best team', and what they look at.
5. Whether a design mock-up is produced and approved before any interface is built (suggested, not required).
6. Whether the menu bar needs an Edit menu for adding and removing tracks, and the exact names of the playlist Open and audio-file Open commands in the File menu.
7. Which window plays a single audio file that is opened on its own, since there is no main window. Decided elsewhere; recorded here because it affects what the person sees.

## Out of scope

- Choosing which surfaces get Liquid Glass.
- Specific behaviour under Reduce Transparency.
- VoiceOver and keyboard-only requirements.
- The list of elements in a playlist window (separate story).
- Support for macOS earlier than 26.
- Custom themes, skins or colour settings.
- Checking that the several places declaring the minimum macOS version agree with each other (covered by the update story).

