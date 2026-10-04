# The app looks and feels like part of macOS

| Field | Value |
|-------|-------|
| ID | 8 |
| Status | proposed |
| Priority | 8 |
| Epic | localplayer-v1 |
| Created | 2026-10-04T11:30:31.130Z |
| Updated | 2026-10-04T11:30:31.130Z |

## Traceability

### Requirements

| Requirement | Title | Addressed by |
|-------------|-------|--------------|
| prd.look.platform | macOS 26 or later | ui.platform.floor |
| prd.look.controls | Standard controls and windows | ui.controls.standard |
| prd.look.menubar | Standard menu bar | ui.controls.standard |
| prd.look.appearance | Follow light and dark appearance | ui.appearance.system |
| prd.look.a11y_respect | Respect system accessibility settings | ui.appearance.system |
| prd.look.glass | Use the system Liquid Glass material | ui.glass.material |
| prd.look.review | Guidelines review for each release | ui.review.hig_checklist |

### Capabilities

| Capability | Build tasks | Test tasks | Tests required | Tests present |
|------------|-------------|------------|----------------|---------------|
| ui.platform.floor | #1 (proposed) | #7 integration (proposed) | integration | integration |
| ui.controls.standard | #2 (proposed) | #8 integration (proposed), #9 e2e (proposed) | integration, e2e | integration, e2e |
| ui.appearance.system | #3 (proposed) | #10 integration (proposed), #11 e2e (proposed) | integration, e2e | integration, e2e |
| ui.glass.material | #4 (proposed) | #12 unit (proposed), #13 integration (proposed) | unit, integration | unit, integration |
| ui.review.hig_checklist | #5 (proposed) | #14 unit (proposed) | unit | unit |

### Gaps

No gaps found.

