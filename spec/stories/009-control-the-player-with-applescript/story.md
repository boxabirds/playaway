# Control the player with AppleScript

| Field | Value |
|-------|-------|
| ID | 9 |
| Status | proposed |
| Priority | 9 |
| Epic | localplayer-v1 |
| Created | 2026-10-04T11:30:43.436Z |
| Updated | 2026-10-04T11:30:43.436Z |

## Traceability

### Requirements

| Requirement | Title | Addressed by |
|-------------|-------|--------------|
| prd.script.parity | Every on-screen action is scriptable | scripting.dictionary.define, scripting.parity.enforce |
| prd.script.parity_gate | Missing scripting equivalents are caught before release | scripting.parity.enforce |
| prd.script.open | Open a file by script | scripting.commands.playback |
| prd.script.transport | Playback commands | scripting.commands.playback |
| prd.script.play_track | Play a chosen track by script | scripting.commands.playback |
| prd.script.modes | Shuffle and repeat by script | scripting.commands.playback |
| prd.script.playlists | Playlist and track management by script | scripting.commands.library |
| prd.script.updates | Check for updates by script | scripting.commands.updates |
| prd.script.state | Reading player state | scripting.state.read |
| prd.script.errors | Refused commands report clearly | scripting.errors.report |
| prd.script.tested | Both routes are regression tested | scripting.tests.dual_path |

### Capabilities

| Capability | Build tasks | Test tasks | Tests required | Tests present |
|------------|-------------|------------|----------------|---------------|
| scripting.dictionary.define | #1 (proposed) | #8 unit (proposed), #9 integration (proposed) | unit, integration | unit, integration |
| scripting.parity.enforce | #2 (proposed) | #10 unit (proposed), #11 integration (proposed) | unit, integration | unit, integration |
| scripting.commands.playback | #3 (proposed) | #12 unit (proposed), #13 integration (proposed), #14 e2e (proposed), #27 integration (proposed) | unit, integration, e2e | unit, integration, e2e |
| scripting.commands.library | #4 (proposed) | #15 integration (proposed), #16 e2e (proposed), #26 unit (proposed) | unit, integration, e2e | integration, e2e, unit |
| scripting.commands.updates | #23 (proposed) | #24 integration (proposed), #25 e2e (proposed) | integration, e2e | integration, e2e |
| scripting.state.read | #5 (proposed) | #17 unit (proposed), #18 integration (proposed), #28 e2e (proposed) | unit, integration | unit, integration, e2e |
| scripting.errors.report | #6 (proposed) | #19 unit (proposed), #20 integration (proposed) | unit, integration | unit, integration |
| scripting.tests.dual_path | #7 (proposed) | #21 integration (proposed), #22 e2e (proposed) | integration, e2e | integration, e2e |

### Gaps

No gaps found.

