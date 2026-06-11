# In-Zone

UWB-based room **zone detection** using 4× Qorvo **DWM3001CDK** anchors and a phone
(iPhone 15 primary, Android secondary). Place anchors around a room, define zones
(bed, desk, window…), and have the phone detect which zone you're in — eventually
firing actions via Shortcuts.

📄 **Full plan:** [docs/SPECIFICATION.md](docs/SPECIFICATION.md)

## Repository layout

| Path | Contents |
|---|---|
| [`docs/`](docs/) | Specification, architecture, and plans |
| [`firmware/`](firmware/) | DWM3001CDK anchor firmware (nRF52833 + DW3110) |
| [`ios/`](ios/) | iOS app (Swift / SwiftUI / NearbyInteraction) |
| [`android/`](android/) | Android app (Kotlin / Compose / androidx.core.uwb) |

## Status

**Firmware builds.** The QANI anchor firmware (nRF52833 + DW3110 + Apple NI) compiles
and links at 175 KB with full UWB session lifecycle, real AES crypto (nrf_oberon),
and bare-metal QOSAL shims.

**iOS app ready.** SwiftUI app with BLE scanning, NI round-robin ranging (2-session
cap), zone capture (Strategy A fingerprinting), and live zone detection. Build with
xcodegen on a Mac — see [`ios/README.md`](ios/README.md).

Next step: flash firmware to DWM3001CDK boards and test end-to-end ranging.

See [§11 Milestones](docs/SPECIFICATION.md#11-milestones). Current target:
**Phase 1** — foreground ranging to 4 anchors, on-screen debug, and live zone
detection on iOS.

## Key constraints driving the design

- iOS allows **max 2 concurrent UWB sessions** → 4 anchors are **time-multiplexed**.
- iOS **background** UWB needs BLE bonding or a Live Activity (iOS 18.4+) → Phase 2.
- Android uses a **different stack** (FiRa via `androidx.core.uwb`), usually **no AoA**.
