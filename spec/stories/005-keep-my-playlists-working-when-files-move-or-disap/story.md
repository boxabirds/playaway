# Keep my playlists working when files move or disappear

| Field | Value |
|-------|-------|
| ID | 5 |
| Status | proposed |
| Priority | 5 |
| Epic | localplayer-v1 |
| Created | 2026-10-04T11:30:15.590Z |
| Updated | 2026-10-04T11:30:15.590Z |

## Traceability

### Requirements

| Requirement | Title | Addressed by |
|-------------|-------|--------------|
| prd.missing.track | Moved files are still found | playlist.track.reference |
| prd.missing.grey | Missing tracks are greyed out | playlist.track.status |
| prd.missing.unplayable | Missing tracks cannot be played | playlist.track.status |
| prd.missing.autoskip | Automatic play-through skips and marks missing tracks | playlist.track.autoskip |
| prd.missing.playmarked | Playing a missing track by double-click is refused and marked | playlist.track.status |
| prd.missing.locate | Locate a missing file | playlist.missing.locate |
| prd.missing.folder | Reconnect other missing tracks from the same folder | playlist.missing.folder_search |
| prd.missing.nonmatch | Unmatched tracks stay missing | playlist.missing.folder_search |
| prd.missing.untouched | Searching never changes audio files | playlist.missing.folder_search |

### Capabilities

| Capability | Build tasks | Test tasks | Tests required | Tests present |
|------------|-------------|------------|----------------|---------------|
| playlist.track.reference | #1 (proposed) | #5 unit (proposed), #6 integration (proposed) | unit, integration | unit, integration |
| playlist.track.status | #2 (proposed) | #7 unit (proposed), #8 integration (proposed), #9 e2e (proposed) | unit, integration, e2e | unit, integration, e2e |
| playlist.track.autoskip | #14 (proposed) | #15 unit (proposed), #16 integration (proposed), #17 e2e (proposed) | unit, integration, e2e | unit, integration, e2e |
| playlist.missing.locate | #3 (proposed) | #10 integration (proposed), #11 e2e (proposed) | integration, e2e | integration, e2e |
| playlist.missing.folder_search | #4 (proposed) | #12 unit (proposed), #13 integration (proposed) | unit, integration | unit, integration |

### Gaps

No gaps found.

