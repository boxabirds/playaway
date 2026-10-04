# PRD

The app tells people when a new version is available, lets them check on demand, and only installs genuine updates on Macs that can run them.

## Problem

An app that is downloaded directly, outside the Mac App Store, has no built-in way to keep itself current. People end up running old versions with known problems, or have to remember to visit a website, download a new copy and replace the old one by hand. An update mechanism that is careless creates a second risk: if an update is not checked, a tampered copy could replace the app. And an update offered to a Mac that cannot run it leaves the person with a broken app.

## Solution

The app looks for newer versions by itself and, when one is available, offers it to the person with a clear choice to install. The person can also ask at any time from the app menu whether they are up to date. Only genuine updates published by the developer are ever installed; anything that cannot be verified is refused with a clear message. Updates are only offered to Macs running macOS 26 or later, so nobody is given a version their Mac cannot run. Every release is signed and notarized by Apple's process, so macOS opens it without a security warning. Checking for updates never slows down the moment the first window appears.

## User Experience

## Golden path
1. The person is using the app. A newer version has been released.
2. The app notices on its own and shows a standard macOS update window saying a new version is available, with the choice to install it, skip it, or be reminded later.
3. The person chooses to install. The app installs the update, restarts and opens the new version.

The person can also choose Check for Updates from the app menu at any time. The app tells them either that a new version is available (and offers it as above) or that they are already up to date.

## Alternate flows
- **Already up to date:** after a manual check the person sees a short message saying they have the latest version. An automatic check shows nothing at all.
- **Update cannot be verified:** the update is not installed. The person sees a message that the update could not be verified, and the app they have keeps working unchanged.
- **Mac cannot run the new version (older than macOS 26):** no update is offered, and no message is shown for it.
- **Cannot reach the update service (for example no internet):** the app keeps working normally. What is shown to the person in this case is not specified yet and is recorded as an open question.

## Empty and error states
- Empty state: a person who has never checked sees nothing related to updates until a new version exists or they choose Check for Updates.
- Error states are the unverifiable-update and unreachable-service cases above.

## Structure
The app menu contains one Check for Updates item. No separate settings pane for updates is part of this story.

## Behaviour
- The first window appears as quickly as it does with updates turned off; checking happens after it is on screen.
- Choosing Check for Updates while a check is already in progress does not start a second one.
- Automatic checking is simply on from the first launch; the person is never asked whether to turn it on.

## Explicit non-behaviours
- Does not install anything without the person choosing to install.
- Does not install an update that cannot be verified.
- Does not offer updates to Macs older than macOS 26.
- Does not collect or send information about what the person plays.
- Does not show update notices for versions the person has chosen to skip.
- Does not ask the person any permission question about checking for updates automatically.

## Offer new versions

> Anchor: `prd.update.prompt`

WHEN a newer version of the app has been released and the Mac runs macOS 26 or later THE SYSTEM SHALL offer that update to the person with a choice to install it.

## Check on demand

> Anchor: `prd.update.manual`

WHEN the person chooses Check for Updates from the app menu THE SYSTEM SHALL check for a newer version and tell the person either that an update is available or that the app is up to date.

## Only offer updates the Mac can run

> Anchor: `prd.update.min_os`

WHILE the Mac runs a macOS version older than the minimum the new release requires THE SYSTEM SHALL NOT offer that update.

## Refuse unverifiable updates

> Anchor: `prd.update.verified`

IF an update cannot be verified as genuinely published by the developer THEN THE SYSTEM SHALL NOT install it and SHALL tell the person that the update could not be verified.

## Updates never delay startup

> Anchor: `prd.update.nonblocking`

WHILE the app is starting THE SYSTEM SHALL NOT delay showing its first window because of update checking.

## No question about automatic checks

> Anchor: `prd.update.no_permission_prompt`

IF the person launches or uses the app, including on a second launch, THEN THE SYSTEM SHALL NOT ask them whether to check for updates automatically.

## Releases open without a security warning

> Anchor: `prd.update.notarized`

WHEN a release is published THE SYSTEM SHALL provide it as a signed and Apple-notarized download that macOS opens without a security warning.

## Constraints

- The app runs on macOS 26 and later only.
- Distributed outside the Mac App Store; the app is not sandboxed.
- Update signing keys belong to this product alone and are never shared with another product.
- Product name, bundle identifier and the names of the update hosting and release locations are not decided yet; this story must not invent them.
- The launch-time target for the first window is covered by the launch-speed story.

## Out of scope

- What the person sees when the update service cannot be reached.
- Whether an update prompt may appear while audio is playing, and whether an install may interrupt playback.
- Release notes shown inside the update window (open).
- A settings pane for update preferences.
- Delta (partial) updates and beta channels.
- Mac App Store distribution.

