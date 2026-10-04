# Play an audio file straight from Finder

| Field | Value |
|-------|-------|
| ID | 1 |
| Status | proposed |
| Priority | 1 |
| Epic | localplayer-v1 |
| Created | 2026-10-04T11:24:23.142Z |
| Updated | 2026-10-04T11:24:23.142Z |

## Traceability

### Requirements

| Requirement | Title | Addressed by |
|-------------|-------|--------------|
| prd.open.formats | Supported formats | open.format.classify, playback.engine.play_file |
| prd.open.finder | Open by double-clicking in Finder | open.association.register, open.entry.receive |
| prd.open.drag | Open by dragging onto the app icon | open.association.register, open.entry.receive |
| prd.open.menu | Open from the File menu | open.entry.receive |
| prd.open.replace | New file replaces current playback | playback.engine.play_file |
| prd.open.unsupported | Unsupported file notice | open.format.classify, open.unsupported.notice |
| prd.open.nodevice | No audio output device | playback.engine.play_file |
| prd.open.untouched | Opened files are left untouched | open.file.read_only |

### Capabilities

| Capability | Build tasks | Test tasks | Tests required | Tests present |
|------------|-------------|------------|----------------|---------------|
| open.association.register | #1 (proposed) | #10 integration (proposed), #15 e2e (proposed) | integration, e2e | integration, e2e |
| open.format.classify | #2 (proposed) | #7 unit (proposed) | unit | unit |
| playback.engine.play_file | #3 (proposed) | #8 unit (proposed), #11 integration (proposed) | unit, integration | unit, integration |
| open.unsupported.notice | #4 (proposed) | #12 integration (proposed), #16 e2e (proposed), #19 unit (proposed) | integration, e2e | integration, e2e, unit |
| open.entry.receive | #5 (proposed) | #13 integration (proposed), #17 e2e (proposed), #18 integration (proposed) | integration, e2e | integration, e2e |
| open.file.read_only | #6 (proposed) | #9 unit (proposed), #14 integration (proposed) | unit, integration | unit, integration |

### Gaps

No gaps found.

