# Play a whole playlist with shuffle and repeat

| Field | Value |
|-------|-------|
| ID | 2 |
| Status | proposed |
| Priority | 2 |
| Epic | localplayer-v1 |
| Created | 2026-10-04T11:29:59.982Z |
| Updated | 2026-10-04T11:29:59.982Z |

## Traceability

### Requirements

| Requirement | Title | Addressed by |
|-------------|-------|--------------|
| prd.playlist.order | Play in listed order | playlist.playback.advance |
| prd.playlist.start | Starting a playlist takes over playback | playlist.playback.start |
| prd.playlist.play_track | Double-clicking a track plays it | playlist.playback.play_track |
| prd.playlist.play_track_shuffle | Shuffle carries on after the chosen track | playlist.playback.play_track |
| prd.playlist.play_track_blocked | A track that cannot be played is marked, not played | playlist.playback.play_track |
| prd.playlist.advance | Automatic advance | playlist.playback.advance |
| prd.playlist.shuffle | Shuffle plays in random order | playlist.playback.shuffle_order |
| prd.playlist.shuffle_toggle | Shuffle is an on/off control | playlist.controls.modes |
| prd.playlist.repeat_cycle | Repeat steps through three states | playlist.controls.modes |
| prd.playlist.repeat_off | Repeat off stops after the last track | playlist.playback.advance |
| prd.playlist.repeat_all | Repeat all starts the playlist again | playlist.playback.advance |
| prd.playlist.repeat_one | Repeat one replays the track | playlist.playback.advance |
| prd.playlist.independent | Shuffle and Repeat are independent controls | playlist.controls.modes |
| prd.playlist.persist | Settings are remembered | playlist.settings.persist |
| prd.playlist.skip_unreadable | Unreadable tracks are skipped and marked | playlist.playback.skip_unreadable |
| prd.playlist.skip_missing | Missing tracks are skipped and marked | playlist.playback.skip_missing |
| prd.playlist.order_untouched | Shuffle does not rewrite the playlist | playlist.playback.shuffle_order |

### Capabilities

| Capability | Build tasks | Test tasks | Tests required | Tests present |
|------------|-------------|------------|----------------|---------------|
| playlist.playback.advance | #1 (proposed) | #6 unit (proposed), #7 integration (proposed) | unit, integration | unit, integration |
| playlist.playback.shuffle_order | #2 (proposed) | #8 unit (proposed), #9 integration (proposed) | unit, integration | unit, integration |
| playlist.playback.start | #19 (proposed) | #21 unit (proposed), #22 integration (proposed), #23 e2e (proposed) | unit, integration, e2e | unit, integration, e2e |
| playlist.playback.play_track | #27 (proposed) | #28 unit (proposed), #29 integration (proposed), #30 e2e (proposed) | unit, integration, e2e | unit, integration, e2e |
| playlist.playback.skip_unreadable | #3 (proposed) | #10 unit (proposed), #11 integration (proposed), #12 e2e (proposed) | unit, integration, e2e | unit, integration, e2e |
| playlist.playback.skip_missing | #20 (proposed) | #24 unit (proposed), #25 integration (proposed), #26 e2e (proposed) | unit, integration, e2e | unit, integration, e2e |
| playlist.controls.modes | #4 (proposed) | #13 unit (proposed), #14 integration (proposed), #15 e2e (proposed) | unit, integration, e2e | unit, integration, e2e |
| playlist.settings.persist | #5 (proposed) | #16 unit (proposed), #17 integration (proposed), #18 e2e (proposed) | unit, integration, e2e | unit, integration, e2e |

### Gaps

No gaps found.

