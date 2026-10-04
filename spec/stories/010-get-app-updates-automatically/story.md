# Get app updates automatically

| Field | Value |
|-------|-------|
| ID | 10 |
| Status | proposed |
| Priority | 10 |
| Epic | localplayer-v1 |
| Created | 2026-10-04T11:30:46.989Z |
| Updated | 2026-10-04T11:30:46.989Z |

## Traceability

### Requirements

| Requirement | Title | Addressed by |
|-------------|-------|--------------|
| prd.update.prompt | Offer new versions | updates.sparkle.configure, updates.controller.lifecycle, updates.release.publish |
| prd.update.manual | Check on demand | updates.menu.check, updates.verify.selftest |
| prd.update.min_os | Only offer updates the Mac can run | updates.release.publish, updates.version.consistency |
| prd.update.verified | Refuse unverifiable updates | updates.sparkle.configure, updates.release.publish, updates.verify.selftest |
| prd.update.nonblocking | Updates never delay startup | updates.controller.lifecycle |
| prd.update.no_permission_prompt | No question about automatic checks | updates.sparkle.configure |
| prd.update.notarized | Releases open without a security warning | updates.build.package |

### Capabilities

| Capability | Build tasks | Test tasks | Tests required | Tests present |
|------------|-------------|------------|----------------|---------------|
| updates.sparkle.configure | #1 (proposed) | #8 unit (proposed), #9 integration (proposed), #26 integration (proposed), #27 e2e (proposed) | unit, integration | unit, integration, e2e |
| updates.controller.lifecycle | #2 (proposed) | #10 unit (proposed), #11 integration (proposed), #12 e2e (proposed) | unit, integration, e2e | unit, integration, e2e |
| updates.menu.check | #3 (proposed) | #13 unit (proposed), #14 integration (proposed), #15 e2e (proposed), #25 integration (proposed) | unit, integration, e2e | unit, integration, e2e |
| updates.build.package | #4 (proposed) | #16 integration (proposed), #17 e2e (proposed) | integration, e2e | integration, e2e |
| updates.release.publish | #5 (proposed) | #18 unit (proposed), #19 integration (proposed), #20 e2e (proposed) | unit, integration, e2e | unit, integration, e2e |
| updates.version.consistency | #6 (proposed) | #21 unit (proposed), #22 integration (proposed) | unit, integration | unit, integration |
| updates.verify.selftest | #7 (proposed) | #23 unit (proposed), #24 integration (proposed) | unit, integration | unit, integration |

### Gaps

No gaps found.

