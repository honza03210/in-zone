# In-Zone iOS App

[![iOS](https://github.com/honza03210/in-zone/actions/workflows/ios.yml/badge.svg)](https://github.com/honza03210/in-zone/actions/workflows/ios.yml)

iPhone app for UWB zone detection with DWM3001CDK anchors.

## Prerequisites

- **Xcode 15+** on macOS
- **iPhone 15** (or any UWB-capable iPhone, iOS 16+)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Build

```sh
cd ios/InZone
xcodegen generate        # creates InZone.xcodeproj from project.yml
open InZone.xcodeproj
```

In Xcode:
1. Select your **Development Team** under Signing & Capabilities
2. The **Nearby Interaction Accessory** entitlement may require configuration
   in the Apple Developer portal — add it to your App ID if Xcode flags it
3. Connect your iPhone, select it as the run destination
4. **Cmd+R** to build and run

## Usage

### 1. Discover anchors
Go to the **Anchors** tab, tap **Scan**. Anchors advertising as `InZone-A0`
through `InZone-A3` will appear. Tap **Connect** on each one.

### 2. Start ranging
Switch to the **Live** tab and tap **Start Ranging**. The app round-robins
NI sessions across connected anchors (max 2 concurrent, ~400 ms dwell each).
Per-anchor distances update in the card grid.

### 3. Capture zones
With ranging active, go to the **Zones** tab and tap **+**. Name the zone,
pick a color, then tap **Capture Position** — hold the phone still for
2 seconds while it records the distance fingerprint. Save.

### 4. Live zone detection
Back on the **Live** tab, toggle **Zone Detection** on. The banner shows
which captured zone you're closest to, with hysteresis to prevent flickering.

## Architecture

```
InZone/
  Models/        Anchor, Zone (fingerprint = [anchorId -> mean/variance])
  BLE/           CoreBluetooth scanning, connection, NI protocol messages
  Ranging/       NISession management, round-robin scheduler (2-session cap)
  Zone/          Strategy A fingerprint matching, EMA filter, JSON persistence
  Views/         SwiftUI: Anchors, Live, ZoneSetup, ZoneList
```

See [docs/SPECIFICATION.md](../docs/SPECIFICATION.md) for the full system design.

## Continuous Integration

[`.github/workflows/ios.yml`](../.github/workflows/ios.yml) runs on every push to
`main` and on pull requests touching `ios/**`. On a macOS runner it installs
XcodeGen, regenerates the project, and runs the full unit-test suite on the iOS
Simulator (`xcodebuild test`). The `.xcresult` bundle is uploaded as a build
artifact. No code signing is required — tests run unsigned on the simulator.

The same workflow also builds an **unsigned `.ipa`** (artifact `InZone-unsigned-ipa`)
on pushes to `main`, for sideloading via AltStore/SideStore with a free Apple ID.
Note: real UWB ranging needs the **Nearby Interaction** entitlement, which a free
account can't grant — the app installs and the BLE/handshake works, but the NI
session stalls (visible in the Live → Debug panel as `sess=1, shr=0`). For real
ranging use the TestFlight path below.

## TestFlight (real ranging — needs a paid Apple Developer account)

[`.github/workflows/ios-testflight.yml`](../.github/workflows/ios-testflight.yml)
archives a properly signed build and uploads it to TestFlight, entitlement and
all — no Mac, no cable, no AltStore. Install it over the air via the TestFlight
app; internal testing needs no App Review.

One-time setup:
1. Join the Apple Developer Program ($99/yr).
2. App Store Connect → create the app record with bundle id `com.inzoned.app`.
3. App Store Connect → Users and Access → Integrations → App Store Connect API →
   generate a key (Developer/App Manager access). Download the `.p8` **once**;
   note its **Key ID** and the **Issuer ID**. (Used only to authenticate the
   upload.)
4. Find your **Team ID** (10 chars) on the Membership page.
5. Create a **fixed Apple Distribution certificate + App Store provisioning
   profile** and add the signing secrets — see
   [docs/ios-testflight-signing.md](../docs/ios-testflight-signing.md) (no Mac
   needed). Then add the upload secrets too: `ASC_KEY_ID`, `ASC_ISSUER_ID`,
   `ASC_KEY_P8`, `APPLE_TEAM_ID`.
6. Actions tab → **iOS TestFlight** → **Run workflow**. The build number is set
   from the run number automatically, so each run is uploadable.
7. After App Store Connect finishes processing (~5–30 min), open the TestFlight
   app on the iPhone (add yourself as an internal tester) and install. Builds
   last 90 days.

The workflow signs **manually** with that one certificate/profile — *not*
`-allowProvisioningUpdates`/automatic, which regenerates a distribution
certificate on every run and exhausts Apple's limit (causing
"No profiles for 'com.inzoned.app' were found"). One cert, reused every build.
