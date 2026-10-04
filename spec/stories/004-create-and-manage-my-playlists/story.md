# Create and manage my playlists

| Field | Value |
|-------|-------|
| ID | 4 |
| Status | proposed |
| Priority | 4 |
| Epic | localplayer-v1 |
| Created | 2026-10-04T11:30:12.005Z |
| Updated | 2026-10-04T11:30:12.005Z |

## Traceability

### Requirements

| Requirement | Title | Addressed by |
|-------------|-------|--------------|
| prd.playlist.create | Create a playlist | playlist.document.lifecycle |
| prd.playlist.save_location | First save uses the standard Save panel | playlist.document.lifecycle |
| prd.playlist.autosave | Changes are saved automatically | playlist.document.lifecycle |
| prd.playlist.open | Open a playlist | playlist.store.load |
| prd.playlist.open_once | An open playlist is not opened twice | playlist.document.lifecycle |
| prd.playlist.rename | Rename a playlist | playlist.document.lifecycle |
| prd.playlist.add | Add files to a playlist | playlist.model.edit, playlist.ui.editor |
| prd.playlist.remove | Remove files from a playlist | playlist.model.edit, playlist.ui.editor |
| prd.playlist.reorder | Reorder files in a playlist | playlist.model.edit, playlist.ui.editor |
| prd.playlist.reject_unsupported | Unsupported files are declined | playlist.model.edit, playlist.ui.editor |
| prd.playlist.persist | Changes persist across launches | playlist.store.save, playlist.store.load |
| prd.playlist.save_safe | Failed or interrupted saves are safe | playlist.store.save, playlist.ui.editor |
| prd.playlist.self_update | The app keeps a playlist up to date by itself | playlist.store.save |
| prd.playlist.audio_untouched | Removing a file never changes the audio file | playlist.model.edit |
| prd.playlist.own_file | Each playlist is an ordinary file | playlist.store.save |
| prd.playlist.doctype | Finder recognises playlists | playlist.doctype.declare |

### Capabilities

| Capability | Build tasks | Test tasks | Tests required | Tests present |
|------------|-------------|------------|----------------|---------------|
| playlist.model.edit | #1 (proposed) | #6 unit (proposed) | unit | unit |
| playlist.store.save | #2 (proposed) | #7 unit (proposed), #8 integration (proposed) | unit, integration | unit, integration |
| playlist.store.load | #3 (proposed) | #9 unit (proposed), #10 integration (proposed) | unit, integration | unit, integration |
| playlist.document.lifecycle | #4 (proposed) | #12 integration (proposed), #14 e2e (proposed) | integration, e2e | integration, e2e |
| playlist.ui.editor | #5 (proposed) | #13 integration (proposed), #17 e2e (proposed) | integration, e2e | integration, e2e |
| playlist.doctype.declare | #15 (proposed) | #16 integration (proposed) | integration | integration |

### Gaps

No gaps found.

