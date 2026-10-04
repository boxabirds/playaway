# Tasks

| # | Title | Status | Type | Implements |
|---|-------|--------|------|------------|
| 1 | Declare macOS 26 as the platform floor in the package manifest and Info.plist | proposed | implementation | ui.platform.floor |
| 2 | Build the standard menu bar, File document commands and playlist window from system controls | proposed | implementation | ui.controls.standard |
| 3 | Implement read-only AppearanceModel and live appearance updates | proposed | implementation | ui.appearance.system |
| 4 | Add the GlassSurface wrapper over the system Liquid Glass material | proposed | implementation | ui.glass.material |
| 5 | Write the HIG checklist and its release-blocking validator | proposed | implementation | ui.review.hig_checklist |
| 7 | Integration tests: built Info.plist and package manifest declare macOS 26 | proposed | test:integration | ui.platform.floor |
| 8 | Integration tests: playlist window and menus use system controls only | proposed | test:integration | ui.controls.standard |
| 9 | E2E tests: real menu bar, File menu commands and one window per playlist | proposed | test:e2e | ui.controls.standard |
| 10 | Integration tests: appearance by accessibility setting by surface matrix | proposed | test:integration | ui.appearance.system |
| 11 | E2E tests: real appearance switch and real accessibility setting left untouched | proposed | test:e2e | ui.appearance.system |
| 12 | Unit tests: GlassSurface returns only the system material | proposed | test:unit | ui.glass.material |
| 13 | Integration tests: no custom glass imitation in the rendered view tree | proposed | test:integration | ui.glass.material |
| 14 | Unit tests: HIG checklist validation states | proposed | test:unit | ui.review.hig_checklist |

## Details

### 1. Declare macOS 26 as the platform floor in the package manifest and Info.plist

Set platforms to .macOS(.v26) in Package.swift and LSMinimumSystemVersion 26.0 in Resources/Info.plist. This task only DECLARES the floor: no validator, no PlatformFloor or validatePlatformFloor types and no script belong here. Agreement between the Info.plist, the package manifest and the appcast minimum version is checked in one place only, by the update story's updates.version.consistency capability (scripts/check-min-os.sh). Verify with TC-40 and TC-41.

### 2. Build the standard menu bar, File document commands and playlist window from system controls

Implement AppMenu.makeMenuBar with the application menu (About, Quit with Cmd-Q), File, Window and Help using standard names, selectors and shortcuts. The File menu holds the standard document commands New Playlist, Open, Open Recent, Close, Save and Rename (supplied by the system document machinery for a document-based app, a proposal) plus the command that opens an audio file (story 1; naming of the two Open commands is provisional). Implement a standard-window PlaylistWindowView using only system views; each playlist document has its own window and there is no main window and no window that lists playlists. No custom title bar, window buttons or drawn controls, and no invented shortcuts that conflict with system ones. Which elements appear in a playlist window is decided by the element-list story, not here. Whether an Edit menu is needed for track add and remove is open (PRD open question 6). Verify with TC-30 to TC-36, TC-72 and TC-76.

### 3. Implement read-only AppearanceModel and live appearance updates

Implement AppearanceModel exposing colorScheme, increaseContrast, reduceTransparency and reduceMotion read from the system with no setters. All open windows redraw when the system appearance changes without a restart; with zero windows a change is a no-op and the next window opens in the current appearance. No app-level appearance or accessibility setting or pane. Visuals under accessibility settings are an open question and must not be invented. Verify with TC-01 to TC-16, TC-20 to TC-25, TC-70, TC-71, TC-75.

### 4. Add the GlassSurface wrapper over the system Liquid Glass material

Implement GlassSurface as the only place glass is created, wrapping the system-provided Liquid Glass effect, with no custom blur, gradient or image imitation. Do not decide which surfaces use it (open question); the app must render correctly with zero glass surfaces. Add the view-tree scan helper that flags custom blur or translucency layers. Verify with TC-50 to TC-52 and TC-72.

### 5. Write the HIG checklist and its release-blocking validator

Create docs/hig-checklist.md with proposed starting items (system controls, menu bar, light/dark, accessibility settings, glass use, window behaviour) each with status pass, fail, exception with reason, or unmarked. Implement validateChecklist and call it from the release script so the release is blocked on unmarked items, fail without exception, an empty file or a missing file. Who signs off is an open question; do not name a person. Verify with TC-60 to TC-65 and TC-74.

### 7. Integration tests: built Info.plist and package manifest declare macOS 26

TC-40: read the built bundle Info.plist and assert LSMinimumSystemVersion is 26.0. TC-41: read Package.swift and assert the platform floor is macOS 26. Negative: no lower value appears anywhere in the bundle metadata. This is inspection of the two declarations only; agreement checking across the appcast, plist and package manifest is the update story's updates.version.consistency, not duplicated here.

### 8. Integration tests: playlist window and menus use system controls only

TC-32 (view tree of a playlist window: every button, slider and menu is a system class, none a custom-drawn subclass), TC-33 (system title bar and window buttons), TC-72 (no custom window-button images or fake glass assets), and the TC-34 shortcut check on the built menu. Render the real playlist window with a realistic 12-row playlist fixture.

### 9. E2E tests: real menu bar, File menu commands and one window per playlist

E2E-1, TC-30, TC-31 and TC-35: launch the built app and read the real menu bar through UI automation; assert application menu, File, Window and Help in order, About and Quit present, Cmd-Q quits, and the File menu contains New Playlist, Open, Open Recent, Close, Save and Rename plus the audio-file open command. E2E-5, TC-36 and TC-76: open two playlist files and assert each is in its own window and no main window or window listing playlists exists.

### 10. Integration tests: appearance by accessibility setting by surface matrix

Implement the integration rows of TC-01 to TC-16 (light/dark x none/Increase Contrast/Reduce Transparency/Reduce Motion x playlist window/alert sheet) by forcing environment values, asserting system-control rendering, no setting write and no app override control (TC-71). Snapshots under accessibility settings are stability references only, not approvals (open questions). Also TC-20, TC-22, TC-23, TC-25 (zero and two playlist windows).

### 11. E2E tests: real appearance switch and real accessibility setting left untouched

E2E-2 (TC-21, TC-24, TC-75: switch real system appearance light to dark and back with a playlist window open, asserting before and after and no restart), E2E-3 and TC-70 (Reduce Transparency on, launch, quit, setting unchanged), TC-09 and TC-13. Proposed E2E-4: accessibility audit of a playlist window, with any known issues recorded as exceptions.

### 12. Unit tests: GlassSurface returns only the system material

TC-50: the helper returns the system glass material for a surface request. Negative: the helper offers no parameter for custom blur, gradient or image. Boundary: zero surfaces requested causes no error.

### 13. Integration tests: no custom glass imitation in the rendered view tree

TC-51: scan the real rendered view tree for custom blur or translucency layers outside the system material and assert none. TC-52: with zero glass surfaces configured the app renders with no glass and no error. TC-72: no fake glass assets in resources.

### 14. Unit tests: HIG checklist validation states

TC-60 (all pass), TC-61 (fail with exception reason passes and lists the exception), TC-62 (fail without exception fails naming the item), TC-63 (unmarked item fails), TC-64 (empty file), TC-65 (missing file names the path), TC-74 (release blocked on fail without exception). Use real checklist files in a temporary directory.

