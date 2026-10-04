# See only what I need on screen

| Field | Value |
|-------|-------|
| ID | 7 |
| Status | proposed |
| Priority | 7 |
| Epic | localplayer-v1 |
| Created | 2026-10-04T11:30:27.381Z |
| Updated | 2026-10-04T11:30:27.381Z |

## Traceability

### Requirements

| Requirement | Title | Addressed by |
|-------------|-------|--------------|
| prd.simple.mapping | Every visible element serves a job | ui.manifest.define, ui.manifest.enforce |
| prd.simple.unmapped | Unrecorded elements are rejected | ui.manifest.enforce |
| prd.simple.stale | Records match what is on screen | ui.manifest.enforce |
| prd.simple.states | The rule holds in every window state | ui.window.enumerate |

### Capabilities

| Capability | Build tasks | Test tasks | Tests required | Tests present |
|------------|-------------|------------|----------------|---------------|
| ui.manifest.define | #1 (proposed) | #4 unit (proposed) | unit | unit |
| ui.window.enumerate | #2 (proposed) | #6 integration (proposed), #8 e2e (proposed) | integration, e2e | integration, e2e |
| ui.manifest.enforce | #3 (proposed) | #5 unit (proposed), #7 integration (proposed), #9 e2e (proposed) | unit, integration, e2e | unit, integration, e2e |

### Gaps

No gaps found.

