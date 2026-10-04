# Tasks

| # | Title | Status | Type | Implements |
|---|-------|--------|------|------------|
| 1 | Implement the launch critical path that presents the first playlist document window | proposed | implementation | launch.window.first_paint |
| 3 | Implement the launch-time measurement harness and launch trace | proposed | implementation | launch.measure.harness |
| 4 | Integration tests: first window, restoration and error paths | proposed | test:integration | launch.window.first_paint |
| 5 | E2E tests: measured launch of the signed build on an M2 MacBook Air | proposed | test:e2e | launch.window.first_paint |
| 6 | Unit tests: launch phase ordering and observer notification | proposed | test:unit | launch.window.first_paint |
| 7 | Integration tests: first window precedes updater start and is never delayed by it | proposed | test:integration | launch.window.first_paint |
| 8 | Unit tests: launch verdict boundaries and invalid runs | proposed | test:unit | launch.measure.harness |
| 9 | Integration tests: harness leaves user data untouched and parses a real trace | proposed | test:integration | launch.measure.harness |
| 10 | E2E tests: harness reports cold and warm batches separately on real hardware | proposed | test:e2e | launch.measure.harness |

## Details

### 1. Implement the launch critical path that presents the first playlist document window

Implement LaunchCoordinator, LaunchPhase, LaunchTracing/LaunchTrace, FirstWindowObserver and the launchBudgetMilliseconds constant (1000). Ask the standard document controller to restore the previous session's playlist windows, or create an untitled new-playlist window when nothing is restored or none could be (PROPOSAL pending PRD open question 5). Before the first window is presented do nothing else: no updater, audio engine, network, audio-file access or track-reference resolution. After presentation record the trace, move to WindowShown and notify observers exactly once; story 5's resolver (off main thread) and story 10's UpdaterController are observers, but this task does not implement them. Unreadable restored playlist: still show a window, no blocking dialog. No splash, loading indicator or placeholder. Playlist document and window types belong to story 4 under Sources/LocalPlayer/Playlists/. Verify with TC-36 to TC-40, TC-43, TC-50 to TC-53, TC-55, TC-56.

### 3. Implement the launch-time measurement harness and launch trace

Implement scripts/launch-bench.sh, LaunchVerdictCalculating and the batch result types. Start = timestamp before asking LaunchServices to open the app; stop = first window presented timestamp written by LaunchTrace when a trace path environment variable is set (the trace type itself comes from the launch critical path task; this task adds the harness side and results file). Both are proposals to be confirmed by the owner. Accept a document fixture (nothing to restore, one window, three windows; playlists of 5 or 500 tracks, proposals). Report cold and warm separately, mark cache-purge cold runs as a proxy, mark zero, negative or timed-out runs invalid, fail the batch if any of 10 runs is over budget. Write only to its own results file. Verify with TC-30 to TC-35, TC-41, TC-42 and TC-54.

### 4. Integration tests: first window, restoration and error paths

Cover TC-36 (no restoration data gives an untitled playlist window), TC-37 (unreadable restored playlist still gives a window, no blocking dialog, message wording not asserted), TC-38 (restored playlist with a missing audio file: window presented before any reference is resolved), TC-40 (resolution runs off the main thread and only after WindowShown), TC-52 and TC-53 (no network or audio engine init before the window), TC-55 (over-budget run shows no placeholder), TC-56 (no audio-file access on the main thread before the window). Use real playlist documents in a temp directory, real restoration data, an injected clock and real windows.

### 5. E2E tests: measured launch of the signed build on an M2 MacBook Air

E2E-1 to E2E-3 and rows TC-01 to TC-12 (temperature x documents to restore x playlist size), TC-19 and TC-50. Run on a real M2 MacBook Air against the signed release build with the six proposed document fixtures (none, one window, three windows; 5 and 500 tracks). Report cold and warm separately; cold by restart, or cache purge flagged as proxy. Assert no splash, loading indicator or placeholder appears and that the first window is a playlist window. Gating of cold vs warm stays open per PRD open question 1.

### 6. Unit tests: launch phase ordering and observer notification

Cover TC-39 (trace records Launching then WindowShown, in order) and TC-43 (observers notified exactly once and only after WindowShown). Positive: notification after WindowShown proceeds. Negative: no observer is ever called while the phase is Launching. Use a recording FirstWindowObserver and an injected clock; the updater itself is story 10's, not tested here.

### 7. Integration tests: first window precedes updater start and is never delayed by it

Cover the ordering rows TC-13 to TC-18 and TC-20 to TC-22 (update available and offline, documents D0 D1 D3, and already running) using a recording observer, plus TC-51 (updater not created or started before the first window is presented). Once story 10's real UpdaterController (capability updates.controller.lifecycle) exists, run the same ordering assertions against it. Stubbed network, real windows and real playlist documents.

### 8. Unit tests: launch verdict boundaries and invalid runs

Cover TC-30 (1000 ms within budget), TC-31 (1001 ms over), TC-32 (999 ms within), TC-33 (0 or negative marked invalid), TC-34 (missing stop timestamp marked invalid, never a pass), TC-35 (10 runs with one over budget gives an over-budget batch), TC-41 (trace path variable not set so nothing is written). Also assert cold and warm batches are reported separately.

### 9. Integration tests: harness leaves user data untouched and parses a real trace

TC-54: run the harness against a real build with a document fixture and assert playlist files and audio files are byte-identical afterwards and only the harness results file was written. TC-42: run a real launch with the trace environment variable set and assert a valid first-window timestamp is produced and parsed to the value the app recorded, and that without the variable no trace is written.

### 10. E2E tests: harness reports cold and warm batches separately on real hardware

E2E-1 and E2E-2: the harness runs 10 warm launches and 10 cold launches (restart, or cache purge flagged as proxy) on a real M2 MacBook Air and asserts all timings are reported, valid, with a batch verdict per class and the proxy flag present for purged runs.

