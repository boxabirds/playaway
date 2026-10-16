# Playaway (formerly LocalPlayer) — Technical Architecture (draft)

Status: partial. This is not a complete spec. It focuses on the Sparkle update integration, which is taken from an existing implementation. Everything else is a placeholder to be filled in next.

Companion: `prd.md`.

## Platform

- Native Swift app, macOS 26 minimum.
- Direct distribution: Developer ID signed, notarized, delivered as a DMG. Not sandboxed.
- Updates delivered with Sparkle 2.x.

## Proposed module layout (placeholder)

To be designed in the next pass. The only point settled here is that update code stays isolated from the playback path.

| Module | Responsibility |
|---|---|
| App | Launch, window, menus, Finder/open-file handling |
| Playback | Audio engine, queue, shuffle/repeat state |
| Playlists | Playlist file format, alias resolution, missing-file recovery |
| Scripting | AppleScript dictionary and handlers (UI parity) |
| Updates | Sparkle wiring only |

## Sparkle integration

The reference implementation is Cutaway, in `/Users/julian/expts/macscreencap`. These notes describe what that code does today. Items marked **Change** or **Verify** differ for this app.

### 1. Dependency

Cutaway adds Sparkle as a Swift Package Manager dependency in `ScreencapMenuBar/Package.swift`:

```swift
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
```

and lists `"Sparkle"` in the app target's dependencies. SwiftPM places `Sparkle.framework` and Sparkle's command-line tools (including `sign_update`) in the build artifacts at `.build/artifacts/sparkle/Sparkle/`. Cutaway builds with `swift build` (a SwiftPM executable target), not an Xcode project, and a build script assembles the `.app` bundle by hand.

### 2. Info.plist keys

Cutaway's `Info.plist` carries:

- `SUFeedURL`: an HTTPS URL to `appcast.xml` on Cloudflare Pages.
- `SUPublicEDKey`: the base64 EdDSA public key used to verify downloaded updates.

It also sets `NSAppleScriptEnabled` and `OSAScriptingDefinition` (pointing at an `.sdef` file), which this app needs for AppleScript parity (US-8). That is separate from Sparkle.

**Change:** generate a new EdDSA keypair for this product with Sparkle's `generate_keys` and use its public key. Don't copy Cutaway's key. Sharing a signing key would let a compromise of one product's key sign updates for the other. Store the private key in the keychain and never commit it.

**Change:** `SUFeedURL` points to this product's own appcast, not `cutaway-updates.pages.dev`.

### 3. Updater lifecycle

Cutaway creates the updater in `main.swift` at launch:

```swift
updaterController = SPUStandardUpdaterController(
    startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
```

It is created with `startingUpdater: false` and started later, after onboarding completes. The "Check for Updates…" menu item targets the controller:

```swift
item.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
item.target = updaterController
```

**Change:** this app has no onboarding to wait for, so the deferral has a different purpose. It must not delay showing the playlist window (1s budget, PRD US-5). The proposal is to create the controller without starting it, start it after the first window is on screen, and measure launch with and without it. Whether starting Sparkle measurably affects the launch budget is **Verify**; it hasn't been measured.

### 4. Build, signing, notarization

Cutaway's `build-app.sh` does the following, in order:

1. `swift build -c release --arch arm64 --arch x86_64` for a universal binary.
2. Assembles the `.app` by hand: binary into `Contents/MacOS`, `Info.plist`, the `.sdef` into `Resources`, and `Sparkle.framework` copied into `Contents/Frameworks`.
3. Signs inside-out with hardened runtime and a secure timestamp: first the nested executables, XPC services and helper apps inside `Sparkle.framework`, then the framework, then any dylibs, then the app itself with the entitlements file. The nested-first order is required because Sparkle's framework contains an `.app`, `.xpc` bundles and bare executables.
4. Verifies with `codesign --verify --deep --strict`.
5. Zips the app and submits it with `xcrun notarytool submit --keychain-profile <profile> --wait`.
6. Staples the ticket with `xcrun stapler staple`, retrying once.
7. Packages a DMG with `hdiutil create`.

The signing identity is the first "Developer ID Application" certificate found in the keychain. The notary credentials live in a stored keychain profile named `notarytool-profile`.

**Entitlements.** Cutaway's entitlements file sets camera, audio-input and `network.client`, plus `com.apple.security.cs.disable-library-validation`. It deliberately has no `app-sandbox` key, and `build-app.sh --test-entitlements` asserts that. This app needs no camera or microphone access, so those entries are dropped. Whether `disable-library-validation` is needed here for Sparkle is **Verify**. Library validation normally passes when the app and Sparkle are signed with the same team, and the entitlement weakens the hardened runtime if it isn't needed.

### 5. Release pipeline

`scripts/release.sh` is the single release command (`./scripts/release.sh [version]`). It:

1. Computes the next version, auto-incrementing the last component when none is given, and updates `CFBundleShortVersionString` in `Info.plist`.
2. Commits the version bump.
3. Runs the build script to produce `<App>-<version>.dmg`.
4. Signs the DMG with Sparkle's `sign_update` and extracts the EdDSA signature and byte length.
5. Writes `appcast.xml` with one `<item>`: `sparkle:version`, `sparkle:shortVersionString`, `sparkle:minimumSystemVersion`, and an `<enclosure>` with the download URL, `length` and `sparkle:edSignature`.
6. Deploys the appcast directory to Cloudflare Pages with `wrangler pages deploy`.
7. Tags and pushes, then creates a GitHub release with the DMG attached.

So the appcast is served from Cloudflare Pages, and the DMG itself is downloaded from GitHub Releases.

**Change: `sparkle:minimumSystemVersion` must be `26.0`.** Cutaway's template hardcodes `13.0`, while its `Info.plist` has `LSMinimumSystemVersion` 15.0 and its `Package.swift` has `.macOS(.v15)`. Copying the template unchanged would offer this app's update to Macs that can't run it. The appcast value, `LSMinimumSystemVersion` and the Package platform should all say macOS 26, and a check should fail the release if they disagree.

**Change:** the release script generates a single-item appcast. That means a user who skips several versions gets only the latest, which is fine, but release notes aren't shown. Whether to add release notes is open.

**Change:** new Cloudflare Pages project, new GitHub repository for releases, and new keychain notary profile (or reuse of the existing one). Names are undecided.

### 6. Tests

Cutaway has a Sparkle config test, `sparkle_config_test.swift`, run through launch flags (`--test-sparkle-config` for unit checks, `--test-sparkle-integration` for integration checks). The unit checks assert that:

- `SUFeedURL` is present, uses HTTPS and parses as a URL.
- `SUPublicEDKey` is present, non-empty and looks like base64.
- The Sparkle dependency appears in `Package.swift`.
- The updater can be started after deferred creation, and the menu item's action is `checkForUpdates:`.

**Reuse:** carry the same checks over. Add one that the appcast's minimum system version matches the app's.

## Not yet designed

- Audio engine and format handling for mp3, wav and m4a.
- Playlist file format, extension, and alias storage.
- Finder file association (UTIs, document types) and open-file handling.
- Shuffle and repeat state, and persistence.
- AppleScript dictionary.
- Liquid Glass surfaces and the UI structure.
- Launch-time measurement harness for the 1s target.
- Product name, bundle identifier, repository and hosting names.
