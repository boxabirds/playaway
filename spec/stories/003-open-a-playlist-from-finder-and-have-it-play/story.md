# Open a playlist from Finder and have it play

| Field | Value |
|-------|-------|
| ID | 3 |
| Status | proposed |
| Priority | 3 |
| Epic | localplayer-v1 |
| Created | 2026-10-04T11:30:08.003Z |
| Updated | 2026-10-04T11:30:08.003Z |

## Traceability

### Requirements

| Requirement | Title | Addressed by |
|-------------|-------|--------------|
| prd.plopen.start | Double-clicking a playlist starts it | playlist.open.route |
| prd.plopen.first | Start from the top when shuffle is off | playlist.open.route |
| prd.plopen.random | Start at a random track when shuffle is on | playlist.open.route |
| prd.plopen.front | Already-open playlist comes to the front and starts | playlist.document.focus |
| prd.plopen.nodisturb | Already-playing playlist is left alone | playlist.document.focus |
| prd.plopen.replace | Opening an audio file replaces playlist playback | playlist.playback.replace |
| prd.plopen.settings | Shuffle and repeat settings are not changed | playlist.open.route |
| prd.plopen.unreadable | Unreadable or empty playlist leaves playback alone | playlist.open.route |
| prd.plopen.content | Opening never changes the playlist's content | playlist.open.route |

### Capabilities

| Capability | Build tasks | Test tasks | Tests required | Tests present |
|------------|-------------|------------|----------------|---------------|
| playlist.open.route | #1 (proposed) | #5 unit (proposed), #6 integration (proposed), #9 e2e (proposed) | unit, integration, e2e | unit, integration, e2e |
| playlist.document.focus | #3 (proposed) | #7 integration (proposed), #10 e2e (proposed) | integration, e2e | integration, e2e |
| playlist.playback.replace | #4 (proposed) | #8 integration (proposed), #10 e2e (proposed) | integration, e2e | integration, e2e |

### Gaps

No gaps found.

