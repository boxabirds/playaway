# HIG checklist

Release gate for `prd.look.review` (story 008). The release is blocked unless every item below is `pass`, or is
`exception:` followed by a written reason. Validation: `validateChecklist(at:)` / `runHIGChecklistCheck(path:)`
in `Sources/LocalPlayer/UI/HIGChecklist.swift`.

## Line format

One item per line, starting with `- [`:

    - [item-id] pass
    - [item-id] pass: optional note
    - [item-id] fail
    - [item-id] exception: written reason
    - [item-id] unmarked

Item lines start in column 0 (the indented examples above are not items). Anything else (this prose, indented descriptions) is ignored. Who signs off is an open question and is not named here.

## Marking rule

Mark an item `pass` ONLY when a test in this repository, or a recorded manual review, verifies it, and say which in
the note. Every item is currently `unmarked` on purpose: the starting list is a proposal and nothing below has been
verified yet, so the release gate fails until the owner or the story 008 tests mark them. Do not pre-mark.

## Items (proposed starting list)

- [system-controls] unmarked
  Playlist window uses only system controls (no custom-drawn buttons, sliders or menus). Evidence wanted: view-tree test (TC-32).
- [menu-bar] unmarked
  Application, File, Window and Help menus with standard names, selectors and shortcuts; Cmd-Q quits; no conflicting shortcuts (TC-30 to TC-35).
- [light-dark] unmarked
  Follows the system appearance live without restart; no app-level override (TC-01 to TC-16, TC-21, TC-71, TC-75).
- [accessibility-settings] unmarked
  Increase Contrast, Reduce Transparency and Reduce Motion are read from the system and never written (TC-70, E2E-4 audit).
- [glass-use] unmarked
  Liquid Glass only through the system effect; no custom blur or fake glass assets; renders with zero glass surfaces (TC-50 to TC-52, TC-72).
- [window-behaviour] unmarked
  System title bar and window buttons; one window per playlist document; no main window and no window listing playlists (TC-33, TC-36, TC-76).
- [keyboard-access] unmarked
  Every control reachable and operable by keyboard; visible focus; Full Keyboard Access respected.
- [voiceover-labels] unmarked
  Every control has an accessibility label, role and value that VoiceOver reads correctly.
- [dynamic-type-and-sizing] unmarked
  Text and controls remain legible and unclipped at larger system text sizes and when the window is resized to its minimum.
- [alerts-and-sheets] unmarked
  Errors use system alerts or sheets with standard button names and default/cancel behaviour; no blocking dialog at launch.
- [dock-and-app-lifecycle] unmarked
  Dock icon reopen, Quit and close-last-window behave as a standard document-based Mac app.
- [language-and-naming] unmarked
  Menu, button and alert text follows Apple style (title case for menu items and buttons, sentence case for messages).
