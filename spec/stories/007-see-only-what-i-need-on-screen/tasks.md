# Tasks

| # | Title | Status | Type | Implements |
|---|-------|--------|------|------------|
| 1 | Implement UIManifest loader and the bundled ui-manifest.json | proposed | implementation | ui.manifest.define |
| 2 | Implement WindowEnumerator and the dump-window-elements launch mode | proposed | implementation | ui.window.enumerate |
| 3 | Implement ManifestChecker and the build check that enforces it | proposed | implementation | ui.manifest.enforce |
| 4 | Unit tests: manifest validation boundaries | proposed | test:unit | ui.manifest.define |
| 5 | Unit tests: checker comparison logic and negative cases | proposed | test:unit | ui.manifest.enforce |
| 6 | Integration tests: enumerator over a real fixture playlist window in every state | proposed | test:integration | ui.window.enumerate |
| 7 | Integration tests: checker over real dumps across state and relation | proposed | test:integration | ui.manifest.enforce |
| 8 | E2E tests: real app dump in every state passes with the bundled manifest | proposed | test:e2e | ui.window.enumerate |
| 9 | E2E tests: injected unrecorded view and deleted entry fail the check | proposed | test:e2e | ui.manifest.enforce |

## Details

### 1. Implement UIManifest loader and the bundled ui-manifest.json

Implement UIManifest per the design: per-window-kind entries (only `playlist` valid today), closed Job set, errors emptyFile, malformed, unknownWindowKind, blankElementID, duplicateElementID, unknownJob; never fall back to an empty manifest. Ship Resources/ui-manifest.json (empty or minimal until the element list exists; proposed entries playback.volume and playback.mute with job play_file). Verify with TC-20 to TC-27, TC-34, TC-36, TC-43.

### 2. Implement WindowEnumerator and the dump-window-elements launch mode

Implement WindowEnumerator and the `--dump-window-elements <window-kind> <state>` launch mode over a playlist document window. States: idle, playing, editing_playlist, notice_shown, untitled_empty, reached by in-memory test seams only. Opens a temporary fixture playlist (or a new untitled one), writes nothing to user folders, removes the fixture, prints sorted JSON, exits. stateUnavailable exits nonzero. Verify with TC-31 to TC-33, TC-35, TC-37, TC-42, TC-44, TC-45.

### 3. Implement ManifestChecker and the build check that enforces it

Implement ManifestChecker (pure comparison per window kind) and the build check test that runs on every build: unrecorded, unidentified and stale violations, all reported together, stale = absent from every state of its window kind, invalid manifest never passes. Verify with TC-01 to TC-16 and TC-100 to TC-103 via the checker, and TC-28 to TC-30, TC-40, TC-41, TC-43, TC-46.

### 4. Unit tests: manifest validation boundaries

Cover TC-20 to TC-27 (missing resource, empty entry list, one entry, malformed JSON, blank id, duplicate id, unknown job, each valid job), TC-34 (playback.volume and playback.mute with job play_file accepted) and TC-36 (unknown window kind rejected). Use in-memory bytes for validation cases and the real bundled file for one shape check.

### 5. Unit tests: checker comparison logic and negative cases

Cover TC-28 (entry present in one state only is valid), TC-29 (two violations reported together), TC-30 (zero elements and zero records pass), and negatives TC-40, TC-41, TC-43. Use in-memory manifests and dumps including the untitled_empty state.

### 6. Integration tests: enumerator over a real fixture playlist window in every state

Cover TC-31 (state unavailable), TC-32 (hidden or zero-size views excluded), TC-33 (stable output), TC-35 (volume and mute present in the playing dump), TC-37 (untitled empty opens a new untitled document, nothing written to disk), TC-42 and TC-45 (no modification, no stray fixture files in user folders), TC-46. Real fixture playlist document in a temporary directory; five states.

### 7. Integration tests: checker over real dumps across state and relation

Implement the full state x relation matrix: TC-01 to TC-16 (idle, playing, editing, notice shown) and TC-100 to TC-103 (untitled empty), each with relations agree, unrecorded, stale, unidentified. Run the real checker on real dumps from the fixture playlist window and assert the violation kind and the named element and state.

### 8. E2E tests: real app dump in every state passes with the bundled manifest

E2E-1: launch the built app in dump mode for the playlist window kind in all five states (idle, playing, editing, notice shown, untitled empty), run the checker with the bundled manifest, assert success and no violations. TC-44: the app does not stay running after each dump.

### 9. E2E tests: injected unrecorded view and deleted entry fail the check

E2E-2: inject one unrecorded view in a playlist window through a test-only build flag and assert the check fails naming that view. E2E-3: delete one entry from a copy of the manifest and assert the check fails naming that element. Both across the five window states.

