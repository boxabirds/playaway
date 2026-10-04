# Tasks

| # | Title | Status | Type | Implements |
|---|-------|--------|------|------------|
| 1 | Implement the scripting dictionary and Info.plist scripting keys | proposed | implementation | scripting.dictionary.define |
| 2 | Implement ActionManifest and the build-time parity gate | proposed | implementation | scripting.parity.enforce |
| 3 | Implement playback script commands: open, play, play track, transport, volume, mute, shuffle and repeat | proposed | implementation | scripting.commands.playback |
| 4 | Implement playlist document and track script commands (no delete) | proposed | implementation | scripting.commands.library |
| 5 | Implement read-only state properties on the app delegate | proposed | implementation | scripting.state.read |
| 6 | Implement the script error numbers and mapper | proposed | implementation | scripting.errors.report |
| 7 | Implement the dual-route regression harness and state snapshot helper | proposed | implementation | scripting.tests.dual_path |
| 8 | Unit tests: sdef parses and every entry is documented | proposed | test:unit | scripting.dictionary.define |
| 9 | Integration tests: built bundle is scriptable and ships the dictionary | proposed | test:integration | scripting.dictionary.define |
| 10 | Unit tests: parity comparison logic | proposed | test:unit | scripting.parity.enforce |
| 11 | Integration tests: parity gate stops the real release build | proposed | test:integration | scripting.parity.enforce |
| 12 | Unit tests: playback command validation and argument parsing | proposed | test:unit | scripting.commands.playback |
| 13 | Integration tests: playback script commands via the scripting runtime | proposed | test:integration | scripting.commands.playback |
| 14 | E2E tests: scripted playback and the on-screen controls in the real app | proposed | test:e2e | scripting.commands.playback |
| 15 | Integration tests: playlist and track script commands | proposed | test:integration | scripting.commands.library |
| 16 | E2E tests: scripted playlist management and on-screen playlist actions | proposed | test:e2e | scripting.commands.library |
| 17 | Unit tests: state properties and whitelist | proposed | test:unit | scripting.state.read |
| 18 | Integration tests: reading properties through the scripting runtime | proposed | test:integration | scripting.state.read |
| 19 | Unit tests: error number table and message wording | proposed | test:unit | scripting.errors.report |
| 20 | Integration tests: every refusal leaves state unchanged | proposed | test:integration | scripting.errors.report |
| 21 | Integration tests: dual-route suite covers every manifest action | proposed | test:integration | scripting.tests.dual_path |
| 22 | E2E tests: UI route versus script route state equivalence | proposed | test:e2e | scripting.tests.dual_path |
| 23 | Implement the check for updates script command | proposed | implementation | scripting.commands.updates |
| 24 | Integration tests: check for updates script command | proposed | test:integration | scripting.commands.updates |
| 25 | E2E tests: check for updates by script and by menu | proposed | test:e2e | scripting.commands.updates |
| 26 | Unit tests: playlist script command argument validation | proposed | test:unit | scripting.commands.library |
| 27 | Integration tests: play track and previous-track edges by script match the UI route | proposed | test:integration | scripting.commands.playback |
| 28 | E2E tests: volume and mute saved across relaunch for script and UI routes | proposed | test:e2e | scripting.state.read |

## Details

### 1. Implement the scripting dictionary and Info.plist scripting keys

Create Resources/LocalPlayer.sdef and the Info.plist scripting keys (NSAppleScriptEnabled true, OSAScriptingDefinition LocalPlayer.sdef) following Cutaway's pattern. One command or property per app-specific manifest action, 19 in all including `play track` (1-based position, playlist), with a description and handler key each; read properties for playing, current track, position, duration, volume, muted; read/write volume, muted, shuffle, repeat; open playlist documents addressed by name. No delete-playlist command and no entry for the excluded system items. Copy the sdef into Contents/Resources in the build script. Verify with TC-59, TC-60, TC-72, TC-76, TC-77, E2E-5.

### 2. Implement ActionManifest and the build-time parity gate

Implement ActionManifest (id, uiBinding, scriptBinding for all 19 actions including play track), the ExcludedSystemItems list (about, quit, hide, services, windowMenu, helpMenu) and the ParityGate comparison, invoked by a launch flag and from the build script before signing. The gate fails naming each app-specific UI action without a script entry and each script entry without a UI action. Verify with TC-61 to TC-66, TC-68.

### 3. Implement playback script commands: open, play, play track, transport, volume, mute, shuffle and repeat

Implement NSScriptCommand subclasses for open, play, play track, pause, stop, seek, next track and previous track, and KVC read/write properties volume (0 to 100 using scriptVolumeMin/scriptVolumeMax named constants, mapped to the engine's 0.0 to 1.0), muted, shuffle and repeat. Each command validates then calls the same handler the matching control calls (OpenCoordinator.open; the control-playback handlers over PlaybackEngine; PlaylistPlayer.play(track:) for play track). Volume and mute set by script are saved through the same settings path as the on-screen controls so saved values are identical across routes. Previous track must match the on-screen control, including first-track wrap (repeat on goes to the last track, repeat off does nothing, shuffle on goes back through the shuffled order: interpretation pending owner confirmation). Play track: error 1001 playlist not open, 1006 position out of range, 1004 for a missing track, replaces anything playing. Setting muted to its current value is not an error. Verify with TC-01 to TC-22, TC-37, TC-38, TC-41 to TC-45, TC-50 to TC-52, TC-78 to TC-87.

### 4. Implement playlist document and track script commands (no delete)

Implement make playlist (optional name or full path; name only saves into Documents, full path saves there, neither stays untitled; provisional), rename playlist (renames the document's file), add track, remove track, move track and locate, all addressing OPEN playlist documents by name and calling the same handlers as the UI under Sources/LocalPlayer/Playlists/. Open playlist documents are an element of the application. NO delete-playlist command and no code path deleting audio or playlist files. Errors: 1001 playlist not open (No open playlist named X), 1003, 1004, 1005 unwritable save location, 1006, 1007, 1008. File: Sources/LocalPlayer/Scripting/LibraryScriptCommands.swift. Verify with TC-23 to TC-34, TC-40, TC-46, TC-47, TC-53 to TC-56, TC-74.

### 5. Implement read-only state properties on the app delegate

Implement read-only KVC properties on the app delegate in Sources/LocalPlayer/Scripting/AppDelegate+Scripting.swift: scriptIsPlaying, scriptCurrentTrack, scriptPosition, scriptVolume, scriptMuted, scriptShuffle, scriptRepeat, with a static scriptKVCKeys whitelist consulted by application(_:delegateHandlesKey:). Idle defaults when the app is not ready. Reading never changes state. Position, volume and muted come from PlaybackEngine properties owned by the control-playback story. Verify with TC-57, TC-58, TC-71.

### 6. Implement the script error numbers and mapper

Implement ScriptError constants and the mapper in Sources/LocalPlayer/Scripting/ScriptError.swift: 1001 no such open playlist, 1002 nothing playing, 1003 unsupported file (same wording as the on-screen notice), 1004 file not found, 1005 invalid parameter (seek or volume out of range, unwritable save location), 1006 no such track, 1007 missing file could not be located, 1008 app not ready (including update service not started). Numbers are proposals pending owner confirmation. Unmapped failures return 1005 with the reason. Verify with TC-40 to TC-49, TC-56, TC-70.

### 7. Implement the dual-route regression harness and state snapshot helper

Implement the dual-route regression harness and state snapshot helper: for each of the 18 manifest actions run one UI-route case and one AppleScript-route case and compare the resulting player and playlist snapshots; fail when a manifest entry has no dual-route case. Files: Tests/LocalPlayerTests/Scripting/DualPathTests.swift, Tests/LocalPlayerE2E/DualPathUITests.swift, shared snapshot helper. Verify with TC-01 to TC-36, TC-67, TC-68.

### 8. Unit tests: sdef parses and every entry is documented

Unit tests: TC-59 the sdef parses, every entry has a description and handler key; TC-72 no sdef command or property lacks a manifest action; TC-76 no command that deletes a playlist exists; TC-77 no entry for About, Quit, Hide, Services, Window menu or Help menu. Positive: all 18 app-specific actions have an entry.

### 9. Integration tests: built bundle is scriptable and ships the dictionary

Integration test TC-60: the built bundle Info.plist has NSAppleScriptEnabled true and OSAScriptingDefinition names LocalPlayer.sdef, and that file exists in Contents/Resources. Negative: an sdef missing from the bundle fails the check.

### 10. Unit tests: parity comparison logic

Unit tests for the parity comparison: TC-61 UI action with no script entry fails and names it; TC-62 script entry with no UI action fails and names it; TC-63 matching sets pass; TC-64 About, Quit, Hide, Services, Window menu and Help menu with no script entry pass because they are on ExcludedSystemItems; TC-65 an app-specific menu item not on the excluded list with no script entry fails and names it.

### 11. Integration tests: parity gate stops the real release build

Integration test TC-66: run the gate inside the real release build script against a fixture with a deliberate scripting gap and assert the build exits non-zero before signing. Positive: with parity restored the gate lets the build continue to signing.

### 12. Unit tests: playback command validation and argument parsing

Unit tests for playback command validation and argument parsing: seek 0 and exactly duration accepted, negative and beyond duration refused (1005); volume 0 and 100 accepted, -1 and 101 refused (1005) with the 0 to 100 to 0.0 to 1.0 mapping; muted true twice accepted; play track position 0 and N+1 refused (1006); play track on an unknown playlist (1001); play track on a missing track (1004). Covers TC-44, TC-45, TC-50 to TC-52, TC-84, TC-85, TC-86.

### 13. Integration tests: playback script commands via the scripting runtime

Integration tests for playback script commands through the real scripting runtime and action handlers with a recording sink: open, play, pause, stop, seek, next, previous, volume, mute, shuffle, repeat (TC-02 to TC-22 script rows and equivalence to the UI-route state), play track (TC-38, TC-87), error rows TC-41 to TC-45, and persistence of shuffle, repeat, volume and mute through the same settings path as the UI (TC-79, isolated settings suite). Assert state before and after each call.

### 14. E2E tests: scripted playback and the on-screen controls in the real app

E2E tests for scripted playback and the on-screen controls in the real app: the UI rows TC-01 to TC-22 and TC-37 (double-click a track row) against the built app with UI automation, plus E2E-1 and E2E-3 via osascript. Assert the window updates live for scripted changes and that only one thing plays at a time.

### 15. Integration tests: playlist and track script commands

Integration tests: playlist document script commands through the real runtime and a temporary folder: AppleScript-route rows TC-24, TC-26, TC-28, TC-30, TC-32, TC-34; errors TC-40 (No open playlist named X), TC-46, TC-47; TC-53 (0 and 1 track remove and reorder), TC-54 (name only saves into Documents, provisional, use a redirected Documents folder), TC-55, TC-56 (unwritable path gives 1005 and no file created); TC-74 (no audio file or playlist file deleted or moved by any command).

### 16. E2E tests: scripted playlist management and on-screen playlist actions

E2E tests: UI-route rows TC-23, TC-25, TC-27, TC-29, TC-31, TC-33 in the real app and E2E-2 (osascript: make playlist saved as Morning in a temporary folder, add three files, move track 3 to 1, play; the playlist window shows the new order and playback follows). Assert no delete-playlist command is offered anywhere in the UI or dictionary.

### 17. Unit tests: state properties and whitelist

Unit tests for state properties and the whitelist: read playing, current track, position, volume, muted, shuffle and repeat in idle, playing and paused states (idle defaults are the saved settings); before and after snapshots identical; a key outside the whitelist is not handled. Covers TC-57, TC-58, TC-71.

### 18. Integration tests: reading properties through the scripting runtime

Integration tests for reading properties through the real scripting runtime: every property in idle, playing and paused states, volume and muted read as saved values after a settings reload (isolated settings suite, simulating relaunch), and a read never changes state or starts playback. Covers TC-57, TC-58, TC-71 at the runtime boundary and the saved-value side of TC-88 to TC-91.

### 19. Unit tests: error number table and message wording

Unit tests for the error number table and message wording: 1001 No open playlist named X, 1002 nothing playing, 1003 same wording as the on-screen unsupported notice, 1004 file not found (including play track on a missing track), 1005 invalid parameter (seek, volume, unwritable save location), 1006 no such track, 1007 missing file could not be located, 1008 app not ready (including update service not started); an unmapped failure returns 1005 with the reason. Numbers are accepted for now and may change before first release. Covers TC-40 to TC-49, TC-84 to TC-86.

### 20. Integration tests: every refusal leaves state unchanged

Integration tests: every refusal in TC-40 to TC-49 and TC-56 leaves playback, volume, playlists, settings and files exactly as before (TC-70). Take a state snapshot before and after each refused command and assert equality, including volume and muted.

### 21. Integration tests: dual-route suite covers every manifest action

Integration tests that the dual-route suite covers every manifest action: with 19 entries (including play track) the suite reports 19 UI cases and 19 script cases (TC-68); adding a manifest entry with no dual-route case makes the suite fail naming the entry (TC-67).

### 22. E2E tests: UI route versus script route state equivalence

E2E tests: UI route versus script route state equivalence on the same fixture for all 19 actions (E2E-4, including play track TC-37 versus TC-38), snapshot compare of final player and playlist state, plus E2E-5 (dictionary view lists every entry, no delete playlist command).

### 23. Implement the check for updates script command

Add CheckForUpdatesCommand calling the same action handler as the Check for Updates menu item, which uses the updates story's UpdaterController check. While the update service has not started return error 1008 and start no check. Nothing is installed without the person choosing. Add the command to the sdef and the ActionManifest (F18). Verify with TC-35, TC-36, TC-49.

### 24. Integration tests: check for updates script command

TC-36: the script command starts exactly one update check through a recording stub, same as the menu route in TC-35. TC-49: while the update service has not started the command returns 1008 and the stub records no check. Negative: no install happens and state is unchanged on refusal.

### 25. E2E tests: check for updates by script and by menu

TC-35 choose Check for Updates in the app menu of the real app and E2E-6: osascript check for updates against a local fixture feed. Assert the same update window or up-to-date message appears by both routes and nothing is installed without choosing.

### 26. Unit tests: playlist script command argument validation

Unit tests for library command validation: playlist name not open maps to 1001 (TC-40); track index 0 and N+1 map to 1006 (TC-46); remove on a 0 track and 1 track playlist and reorder 1 to 1 as a no-op (TC-53); make playlist argument forms name only, full path, neither resolve to the documented save targets (TC-54, TC-55) and an unwritable path maps to 1005 (TC-56). No command is defined that deletes a playlist.

### 27. Integration tests: play track and previous-track edges by script match the UI route

Integration tests with a recording sink and real playlist fixtures: previous track at the first track with repeat off, repeat all, and shuffle on (seeded pass, going back; wrap with repeat all) compared to the UI route (TC-80 to TC-83, rule is interpretation pending owner confirmation); play track at first and last position (TC-87), position 0 and N+1 (TC-84, 1006), missing track (TC-85, 1004, nothing plays), playlist not open (TC-86, 1001); a play track while another track plays leaves one thing playing (TC-78).

### 28. E2E tests: volume and mute saved across relaunch for script and UI routes

E2E against the built app: set volume 30 by osascript, quit, relaunch, read volume (TC-88); set volume 30 with the on-screen control, quit, relaunch, read by script (TC-89); same for muted true (TC-90, TC-91), volume value unchanged by muting; E2E-7 combined workflow including play track by script and by double-click starting the same track.

