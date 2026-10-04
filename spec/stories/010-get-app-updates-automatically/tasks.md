# Tasks

| # | Title | Status | Type | Implements |
|---|-------|--------|------|------------|
| 1 | Add Sparkle dependency, Info.plist keys and configuration validation | proposed | implementation | updates.sparkle.configure |
| 2 | Implement UpdaterController with start-after-first-window | proposed | implementation | updates.controller.lifecycle |
| 3 | Add the Check for Updates menu item | proposed | implementation | updates.menu.check |
| 4 | Port build-app.sh for signing, notarizing and DMG packaging | proposed | implementation | updates.build.package |
| 5 | Port release.sh to sign, publish the appcast and create the release | proposed | implementation | updates.release.publish |
| 6 | Add the minimum macOS version consistency check | proposed | implementation | updates.version.consistency |
| 7 | Port the Sparkle self-test flags | proposed | implementation | updates.verify.selftest |
| 8 | Unit tests: update configuration validation | proposed | test:unit | updates.sparkle.configure |
| 9 | Integration tests: Sparkle dependency, debug-only feed override and no shared Cutaway values | proposed | test:integration | updates.sparkle.configure |
| 10 | Unit tests: UpdaterController state logic | proposed | test:unit | updates.controller.lifecycle |
| 11 | Integration tests: scheduled checks across host eligibility and feed content | proposed | test:integration | updates.controller.lifecycle |
| 12 | E2E tests: updater starts after the first window without exceeding the launch budget | proposed | test:e2e | updates.controller.lifecycle |
| 13 | Unit tests: Check for Updates menu item | proposed | test:unit | updates.menu.check |
| 14 | Integration tests: manual check across host eligibility and feed content | proposed | test:integration | updates.menu.check |
| 15 | E2E tests: choose Check for Updates and install, or refuse a tampered update | proposed | test:e2e | updates.menu.check |
| 16 | Integration tests: build script with shimmed notary service | proposed | test:integration | updates.build.package |
| 17 | E2E tests: real notarized build passes Gatekeeper | proposed | test:e2e | updates.build.package |
| 18 | Unit tests: release version selection | proposed | test:unit | updates.release.publish |
| 19 | Integration tests: release script with shimmed hosting and release tools | proposed | test:integration | updates.release.publish |
| 20 | E2E tests: release rehearsal against a staging hosting target | proposed | test:e2e | updates.release.publish |
| 21 | Unit tests: minimum macOS version consistency | proposed | test:unit | updates.version.consistency |
| 22 | Integration tests: release script refuses to publish on version mismatch | proposed | test:integration | updates.version.consistency |
| 23 | Unit tests: self-test output format and exit codes | proposed | test:unit | updates.verify.selftest |
| 24 | Integration tests: self-test integration mode against the fixture feed | proposed | test:integration | updates.verify.selftest |
| 25 | Integration tests: Check for Updates is registered in the AppleScript action manifest | proposed | test:integration | updates.menu.check |
| 26 | Integration tests: no automatic-check permission question on first launch | proposed | test:integration | updates.sparkle.configure |
| 27 | E2E tests (proposed): no automatic-check permission question on a second launch | proposed | test:e2e | updates.sparkle.configure |

## Details

### 1. Add Sparkle dependency, Info.plist keys and configuration validation

Add Sparkle (from 2.0.0) to Package.swift and the app target, add SUFeedURL, SUPublicEDKey and SUEnableAutomaticChecks (true) to Info.plist (feed URL and key as clearly marked placeholders; they are open items, do not invent), and implement validate(_:) returning ConfigIssue values per the design, including the automaticChecksNotEnabled issue when SUEnableAutomaticChecks is missing, false or not a boolean. SUEnableAutomaticChecks is what stops Sparkle asking the person whether to check automatically (the Sparkle behaviour is a VERIFY item). Generate a NEW EdDSA keypair with generate_keys when the owner supplies the key custody decision; never reuse Cutaway's key, never commit the private key. Add the debug-only feed override via the updater delegate, compiled out of release builds. Verify with TC-20 to TC-28, TC-45, TC-88.

### 2. Implement UpdaterController with start-after-first-window

Be the SINGLE owner of UpdaterController: the launch-speed story defines no updater type and only asserts ordering against this one. Wrap SPUStandardUpdaterController created with startingUpdater false. Conform UpdaterController to story 6's FirstWindowObserver and register it with story 6's LaunchCoordinator; firstWindowPresented() calls startAfterFirstWindow(). Expose State notStarted, idle, failed. The signal is raised once for the first window of any kind (restored playlist window or untitled new-playlist window; there is no main window). A second call is ignored; with no window presented, start is not called; invalid configuration moves to failed, logs and disables the menu item. Measure launch with and without the updater started and record the difference (VERIFY item). Verify with TC-30 to TC-34, TC-39 and TC-83.

### 3. Add the Check for Updates menu item

Add one Check for Updates item to the app menu in code, action SPUStandardUpdaterController.checkForUpdates(_:), target the updater controller. Disabled when the controller is failed; choosing it during a running check starts no second check. Register the item in the AppleScript story's ActionManifest (story 9 owns the manifest and the Check for Updates script command): UI binding is this menu item, script binding is the story 9 command, so the parity gate passes without an exclusion. Verify with TC-35 to TC-38.

### 4. Port build-app.sh for signing, notarizing and DMG packaging

Port Cutaway's ScreencapMenuBar/build-app.sh: universal swift build, hand-assembled bundle with Sparkle.framework embedded, inside-out hardened-runtime signing with timestamp, codesign verify deep strict, notarytool submit with keychain profile, stapler with one retry, hdiutil DMG. Entitlements file has no app-sandbox key and drops camera and audio-input; disable-library-validation starts absent (VERIFY item). Keep a --test-entitlements mode. Do not hardcode product name, bundle ID or notary profile (open items). Verify with TC-50 to TC-56.

### 5. Port release.sh to sign, publish the appcast and create the release

Port Cutaway's scripts/release.sh: version bump, run check-min-os first, build, sign_update, extract signature and length, write appcast.xml with minimumSystemVersion read from the single 26.0 source, deploy to hosting, tag, push, create release. Abort before later publish steps on any failure, and refuse to publish while any placeholder remains. Hosting project name and release repository are open items passed as configuration, not hardcoded. Release notes in the appcast are an open item and are not included. Verify with TC-60 to TC-65, TC-85, TC-86.

### 6. Add the minimum macOS version consistency check

Write check-min-os.sh as the single minimum-OS validator in the repository, reading the appcast minimum system version, LSMinimumSystemVersion and the Package.swift platform (the last two are the floor the native-look story declares and delegates here); pass only when all equal 26.0 (26 equals 26.0), otherwise fail naming each disagreeing source, and fail on an unreadable source. release.sh calls it first. Do not add another validator elsewhere. Verify with TC-40 to TC-44 and TC-46.

### 7. Port the Sparkle self-test flags

Port Cutaway's sparkle_config_test.swift behind --test-sparkle-config and --test-sparkle-integration. Add the SUEnableAutomaticChecks check, the min-OS, placeholder and not-Cutaway-key checks and the runtime fixture-feed assertions (manual check completes, altered-signature update refused and bundle unchanged, menu action is checkForUpdates:). No window in test mode, non-zero exit on any failure, fail loudly when the fixture feed address is missing. Verify with TC-70, TC-71 and TC-72.

### 8. Unit tests: update configuration validation

TC-20 to TC-25: feed URL missing, http, invalid; public key missing, empty, not base64, 10 characters or fewer (boundary: 11 passes); placeholder text rejected; Cutaway public key rejected. TC-27: SUEnableAutomaticChecks missing, false and a non-boolean value each yield automaticChecksNotEnabled; TC-28: true passes. Positive: a valid https URL with a real-shaped 44-character base64 key and automatic checks true yields no issues. Assert each failure has its own ConfigIssue.

### 9. Integration tests: Sparkle dependency, debug-only feed override and no shared Cutaway values

TC-26 Package.swift lacks Sparkle fails; TC-45 release build ignores LOCALPLAYER_TEST_FEED_URL and uses the plist feed URL while a debug build honours it; TC-85 scan all repo files for the Cutaway key, feed URL and hosting project; TC-86 release blocked while placeholders remain. Run against the real built bundle and real Info.plist.

### 10. Unit tests: UpdaterController state logic

TC-30 created means notStarted and Sparkle not started; TC-31 first-window signal starts exactly once, state idle; TC-32 second start ignored; TC-33 invalid configuration yields failed, error logged, menu disabled; TC-39 the signal is accepted from a restored playlist window and from an untitled new-playlist window, and with no window presented start is not called; TC-83 start never occurs before the first-window signal. Use a stub updater, assert state before and after each call.

### 11. Integration tests: scheduled checks across host eligibility and feed content

Implement the T1 (scheduled) rows TC-01 to TC-08 and negative TC-80 and TC-82 with the real Sparkle runtime inside the built app, a local appcast host and real signed fixture DMGs. Host below minimum is simulated with an item minimum of 99.0. Feed unreachable rows assert no crash and a usable app only (message text unspecified).

### 12. E2E tests: updater starts after the first window without exceeding the launch budget

TC-34: launch the built app repeatedly with the updater enabled and disabled, measure process start to first window visible (first window of any kind, there is no main window), and assert the difference stays within the launch-story budget (value owned by the launch story, do not invent). Also assert the first scheduled check happens after the window is visible.

### 13. Unit tests: Check for Updates menu item

TC-35 the item exists exactly once with title Check for Updates and action checkForUpdates: targeting the controller; TC-37 item disabled when the controller state is failed and enabled when idle. The cross-story registration (TC-38) is covered by its own integration task.

### 14. Integration tests: manual check across host eligibility and feed content

Implement the T2 integration rows TC-10, TC-12 to TC-16 and TC-36 (second choice during a running check starts no second check) against the real Sparkle runtime and local feed. Up-to-date message shown for same version and for below-minimum host; unreachable feed shows an error without asserting its text.

### 15. E2E tests: choose Check for Updates and install, or refuse a tampered update

TC-09, TC-11, E2E-1, E2E-2, TC-81: with the built app at version A and a local feed, drive the real menu item; E2E-1 installs version B and the app relaunches reporting B; E2E-2 and TC-11 use a one-byte-altered signature, assert the not-verified message and that the app bundle checksum is unchanged.

### 16. Integration tests: build script with shimmed notary service

TC-50 codesign verify deep strict on a real build; TC-51 no Developer ID certificate aborts early; TC-52 notary rejection exits non-zero with log instructions; TC-53 staple fails once then passes; TC-54 staple fails twice exits non-zero; TC-55 entitlements containing app-sandbox aborts the build. Notary tool replaced by a PATH shim; everything else real.

### 17. E2E tests: real notarized build passes Gatekeeper

TC-56 and E2E-3 on a developer machine with the real Developer ID certificate and notary credentials: build, notarize, staple, then run spctl assess and open the DMG; assert accepted with source Notarized Developer ID and no warning dialog. Marked developer-machine only; not run on every CI run.

### 18. Unit tests: release version selection

TC-63 no version given increments the last component (1.0 becomes 1.1, 1.2.3 becomes 1.2.4, single component 1 becomes 1.1); TC-64 explicit version used exactly. Boundary: empty string and malformed version rejected.

### 19. Integration tests: release script with shimmed hosting and release tools

TC-60 empty signature aborts before any publish step; TC-61 appcast item has version, short version, minimumSystemVersion 26.0, enclosure URL, length and edSignature; TC-62 failed deploy means no tag pushed and no release created; TC-65 appcast length equals the real DMG byte length; TC-84 nothing about the person's audio is sent. Hosting and release tools are recording shims; sign_update is real.

### 20. E2E tests: release rehearsal against a staging hosting target

E2E-4: run the full release pipeline against a staging hosting target (name is an open item, do not invent) and assert the appcast is reachable over https and lists the new version with minimumSystemVersion 26.0, and that a built older app finds and verifies it. Requires the owner to supply the staging target.

### 21. Unit tests: minimum macOS version consistency

TC-40 all three 26.0 passes; TC-41 appcast 13.0 fails naming the appcast; TC-42 LSMinimumSystemVersion 15.0 fails naming Info.plist; TC-43 Package platform macOS 15 fails naming Package.swift; TC-44 26 and 26.0 equal. Boundary: missing or unreadable source fails naming that source. This validator is the only minimum-OS check; the native-look story only declares the floor.

### 22. Integration tests: release script refuses to publish on version mismatch

Run the real release.sh with shimmed publish tools and a deliberately mismatched source (each of the three in turn); assert it aborts at the first step, publishes nothing, and names the disagreeing file. TC-46: assert the repository contains exactly one minimum-OS validator script and one validator test, and that it reads the floor the native-look story declares (Package platform and LSMinimumSystemVersion). Also TC-13 to TC-15 and TC-82: a feed item with minimum 99.0 never produces an update window.

### 23. Unit tests: self-test output format and exit codes

TC-70 and TC-20 to TC-28 run through the self-test harness: one printed line per check, non-zero exit on any failure, zero when all pass, missing fixture-feed address fails loudly in integration mode. TC-72: a bundle without SUEnableAutomaticChecks makes the config run print a failing line naming that key and exit non-zero.

### 24. Integration tests: self-test integration mode against the fixture feed

TC-71, TC-03 and TC-11 via --test-sparkle-integration on the built app against the local fixture feed: manual check completes, altered-signature fixture refused with the bundle unchanged, menu action is checkForUpdates:, updater starts after deferred creation.

### 25. Integration tests: Check for Updates is registered in the AppleScript action manifest

TC-38: read the real ActionManifest owned by the AppleScript story (story 9) and assert it has an entry for Check for Updates whose UI binding is this app-menu item and which has a script binding; remove the entry in a copy and assert story 9's parity gate then fails naming the action. Negative: the entry is not in story 9's excluded list of system-standard menu items.

### 26. Integration tests: no automatic-check permission question on first launch

TC-88: launch the built app with valid configuration and clean preferences and assert no permission question about checking for updates automatically is presented and the updater reaches idle. Compare against a bundle built without SUEnableAutomaticChecks only to record (not assert) what Sparkle does, since that behaviour is a VERIFY item.

### 27. E2E tests (proposed): no automatic-check permission question on a second launch

TC-87 and E2E-5, PROPOSED: launch the built app twice against the fixture feed with clean updater preferences and assert no permission question about checking for updates automatically appears on either launch. The test depends on Sparkle behaviour that is unverified in this project (it is believed to ask on the second launch when SUEnableAutomaticChecks is absent); if the behaviour turns out different, the owner decides whether to keep the test.

