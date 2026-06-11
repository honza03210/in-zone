# In-Zone iOS App

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
