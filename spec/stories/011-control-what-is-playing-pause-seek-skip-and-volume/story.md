# Control what is playing: pause, seek, skip and volume

| Field | Value |
|-------|-------|
| ID | 11 |
| Status | proposed |
| Priority | 11 |
| Epic | localplayer-v1 |
| Created | 2026-10-04T11:54:42.412Z |
| Updated | 2026-10-04T11:54:42.412Z |

## Traceability

### Requirements

| Requirement | Title | Addressed by |
|-------------|-------|--------------|
| prd.ctrl.pause | Pause keeps the place | playback.transport.pause_resume |
| prd.ctrl.resume | Play continues from the paused position | playback.transport.pause_resume |
| prd.ctrl.stop | Stop returns to the start | playback.transport.stop |
| prd.ctrl.seek | Seek to a chosen position | playback.transport.seek |
| prd.ctrl.seek_range | Positions outside the track are refused | playback.transport.seek |
| prd.ctrl.next | Next track | playback.transport.skip |
| prd.ctrl.previous | Previous track | playback.transport.skip |
| prd.ctrl.skip_single | Next and Previous do nothing outside a playlist | playback.transport.skip |
| prd.ctrl.volume | Volume changes immediately and stays in range | playback.volume.level |
| prd.ctrl.mute | Mute keeps the chosen volume | playback.volume.mute |
| prd.ctrl.volume_scope | Volume is the player's own level | playback.volume.level |
| prd.ctrl.volume_persist | Volume and Mute are remembered | playback.volume.persist |
| prd.ctrl.state | Controls show the live state | ui.controls.transport |

### Capabilities

| Capability | Build tasks | Test tasks | Tests required | Tests present |
|------------|-------------|------------|----------------|---------------|
| playback.transport.pause_resume | #1 (proposed) | #8 unit (proposed), #9 integration (proposed) | unit, integration | unit, integration |
| playback.transport.stop | #2 (proposed) | #10 unit (proposed), #11 integration (proposed) | unit, integration | unit, integration |
| playback.transport.seek | #3 (proposed) | #12 unit (proposed), #13 integration (proposed) | unit, integration | unit, integration |
| playback.transport.skip | #4 (proposed) | #14 unit (proposed), #15 integration (proposed) | unit, integration | unit, integration |
| playback.volume.level | #5 (proposed) | #16 unit (proposed), #17 integration (proposed) | unit, integration | unit, integration |
| playback.volume.mute | #6 (proposed) | #18 unit (proposed), #19 integration (proposed) | unit, integration | unit, integration |
| playback.volume.persist | #22 (proposed) | #23 unit (proposed), #24 integration (proposed), #25 e2e (proposed) | unit, integration, e2e | unit, integration, e2e |
| ui.controls.transport | #7 (proposed) | #20 integration (proposed), #21 e2e (proposed) | integration, e2e | integration, e2e |

### Gaps

No gaps found.

