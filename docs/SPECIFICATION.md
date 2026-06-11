# In-Zone — UWB Room Zone Detection

> Turn 4 UWB anchors into a room map. Define zones (bed, desk, window…) and trigger
> actions on your phone when you enter them.

- **Status:** Firmware builds (QANI + stub); not yet flashed/tested on hardware
- **Last updated:** 2026-06-10
- **Hardware on hand:** 4× Qorvo **DWM3001CDK** development kits
- **Primary phone:** iPhone 15 (U2 UWB chip), iOS 18+
- **Secondary target:** Android (UWB-capable, e.g. Pixel 8+/Samsung S2x+)

---

## 1. Goal

Place 4 UWB anchors around a room. Open the app, walk around, and "paint" zones
(bed, desk, window, etc.). Once zones are defined, the app detects which zone the
phone is in and fires an action.

- **Phase 1 (this plan's focus):** Foreground app. Live ranging to all anchors,
  on-screen debug (per-anchor distance + direction when available), zone setup,
  and live zone detection.
- **Phase 2:** Background detection + user-configurable actions, ideally via Apple
  **Shortcuts** (`App Intents`) on iOS and equivalents on Android.

---

## 2. Hardware background — DWM3001CDK

| Component | Detail |
|---|---|
| UWB transceiver | Qorvo **DW3110** (FiRa-compliant, Ch 5/9) |
| Host MCU | Nordic **nRF52833** (BLE 5.x, Cortex-M4) |
| Antenna | Single UWB antenna (relevant: limited on-device AoA) |
| Power | USB-C; can run off a USB power bank for placement flexibility |
| Debug/flash | On-board J-Link; flash `.hex` with **J-Flash Lite** / `nrfjprog` |

Qorvo ships a **Nearby Interaction (QANI / QNI)** firmware package (v3.x) for this
board that implements Apple's Nearby Interaction Accessory Protocol. That is the
starting point for the anchor firmware. ([Qorvo product page](https://www.qorvo.com/products/p/DWM3001CDK),
[QNI 3.0 release notes](https://forum.qorvo.com/t/qorvo-nearby-interaction-software-package-v-3-0-release/13390))

---

## 3. The hard constraints (read this first)

These platform limits drive the entire architecture. They are non-obvious and were
the deciding factors in the design below.

### 3.1 iOS allows only **2 concurrent NI sessions**
`NISession` is limited to a **maximum of 2 simultaneous sessions** per device;
exceeding it returns `NIError.Code.activeSessionsLimitExceeded`. The exact cap can
vary by device, so we treat **2 as the ceiling and 1 as the safe default**.

➡️ **Consequence:** We cannot range all 4 anchors at once on iOS. We **round-robin**:
hold 1–2 active sessions, dwell ~0.3–0.5 s to collect samples, then rotate to the
next anchor. A full sweep of 4 anchors lands at roughly **1.5–3 Hz position
updates** — fine for "which zone am I in," not for fast motion tracking.
([Apple forum](https://developer.apple.com/forums/thread/692392))

### 3.2 iOS background UWB is restricted
In the foreground, ranging is unrestricted. In the **background**, an app can only
range with **BLE-paired *and* connected** devices — *or*, on **iOS 18.4+**, with any
supported device if the app launches a **Live Activity** as it backgrounds.
([Apple NI docs](https://developer.apple.com/documentation/nearbyinteraction))

➡️ **Consequence for Phase 2:** Background zone detection requires either (a) BLE
pairing/bonding each anchor, or (b) a persistent Live Activity. Both are designed
for in Phase 2; Phase 1 stays foreground-only and sidesteps this entirely.

### 3.3 Direction (AoA) availability is conditional
On iPhone, **direction is computed by the phone's antenna array**, not the anchor.
`NINearbyObject.direction` is `nil` when the anchor is out of the phone's field of
view, too far, or the phone is held flat. iPhone 15's U2 chip also changed
direction behavior for accessories. **Treat `direction` as best-effort debug data,
not as a primary input** to zone logic.

### 3.4 Android is a *different stack*, not "the same app in Kotlin"
Android does **not** use Apple's NI protocol. It uses **FiRa** ranging via Jetpack
`androidx.core.uwb` (latest `1.0.0-alpha11`, Dec 2025). The phone is **Controller**,
anchors are **Controlees**; the OOB parameter exchange happens over our own BLE GATT
service. A controller **can range multiple controlees**, so Android avoids the iOS
2-session bottleneck — but **most Android phones expose distance only, no AoA**.
The anchor firmware therefore needs a **FiRa/Available-mode build** distinct from the
Apple-NI build. ([Jetpack UWB](https://developer.android.com/jetpack/androidx/releases/core-uwb))

---

## 4. System architecture

```
        ┌─────────────────────────────────────────────────────────┐
        │                         Room                            │
        │   [A0]──────────────────────────────────────[A1]        │
        │    │            (phone walks around)          │         │
        │    │                  📱                       │         │
        │    │                                          │         │
        │   [A3]──────────────────────────────────────[A2]        │
        └─────────────────────────────────────────────────────────┘

  Anchor (DWM3001CDK)                         Phone app
  ┌──────────────────┐   BLE GATT (OOB)   ┌────────────────────────┐
  │ nRF52833 + DW3110 │◀──────────────────▶│ Scan / connect / config │
  │  - BLE advertiser │                    │ Ranging scheduler       │
  │  - NI/FiRa session │◀═══ UWB ranging ══▶│ Position estimator      │
  └──────────────────┘                    │ Zone engine             │
                                          │ Action dispatcher (P2)  │
                                          └────────────────────────┘
```

**Layers in the mobile app (platform-agnostic design, platform-specific impl):**

1. **Transport** — BLE discovery, connect, accessory-config exchange.
2. **Ranging scheduler** — iOS: round-robin across anchors honoring the 2-session
   cap; Android: single multi-controlee session. Emits `(anchorId, distance,
   direction?, timestamp, quality)` samples.
3. **Filtering** — per-anchor smoothing (EMA or 1€ filter) + outlier rejection.
4. **Position / zone engine** — converts the distance vector into either an absolute
   room position or a zone label (see §6).
5. **Zone store** — persisted zone definitions + room/anchor layout.
6. **Action dispatcher** *(Phase 2)* — maps zone-enter/exit events to actions.

---

## 5. Anchor firmware plan (`/firmware`)

**Base:** Qorvo DW3_QM33_SDK_1.1.1 (contains niq library + uwbstack_bundle
pre-compiled static library for FiRa MAC / uwbmac / fira_helper).
**Toolchain:** `arm-none-eabi-gcc` 15.2.1 + GNU Make + nRF5 SDK 17.1.0 Makefile
build system (SoftDevice S113 7.2.0); flash via `nrfjprog` / J-Flash Lite over
on-board J-Link. The uwbstack_bundle is compiled against FreeRTOS/QOSAL but runs
on bare metal via shim implementations in `qosal_shim.c`.

### Tasks
1. **Bring-up:** Flash stock QANI `.hex`, verify ranging against Apple's
   *Nearby Interaction* sample app / Qorvo's reference iOS app.
2. **Anchor identity:** Add a per-device **anchor ID** (0–3) + human label, stored in
   flash (UICR or a settings page). Expose via a BLE characteristic so the app can
   tell anchors apart without hard-coding MAC addresses.
3. **Custom BLE GATT service** ("In-Zone Anchor Service"):
   - `AnchorInfo` (read): id, label, firmware version, build mode (NI vs FiRa).
   - `Config/Control` (write): start/stop ranging, set channel/preamble, set role.
   - Keep Apple's accessory-protocol characteristics intact for the NI build.
4. **Apple-NI build:** Anchor acts as accessory/initiator per Apple's spec; supports
   the phone-driven session start. Confirm it tolerates the phone **tearing down and
   re-establishing** sessions rapidly (our round-robin churns sessions).
5. **FiRa build (for Android):** Anchor as **Controlee**; parameters (session ID,
   channel, preamble, STS, slot/ranging interval) delivered over our GATT service.
6. **Robustness:** Auto-restart advertising after disconnect; watchdog; LED status
   (advertising / connected / ranging); brown-out friendly for power-bank use.
7. *(Stretch)* **Dual-mode** firmware selectable at runtime, so one `.hex` serves
   both platforms.

**Deliverables:** `firmware/README.md` (build + flash steps), prebuilt `.hex` per
build mode, a `PROVISIONING.md` for assigning anchor IDs 0–3.

---

## 6. Position & zone detection (the core algorithm)

We support **two strategies**; ship the simpler one first.

### 6.1 Strategy A — Distance-vector fingerprinting *(MVP, recommended first)*
Treat each location as a vector **d = [d0, d1, d2, d3]** of the 4 anchor distances.
- **Setup:** Stand in a zone, tap "capture." Record the mean distance vector (and
  variance) over ~2 s of samples. A zone = a labeled region in distance-space.
- **Detection:** Current smoothed vector vs each zone's reference; assign the nearest
  within a learned/﻿configurable radius. Use **hysteresis + dwell time** (e.g. must be
  closest for 1 s and 0.5 m better than runner-up) to prevent flicker at borders.
- **Why first:** No anchor coordinates, no room geometry, no trilateration math, and
  it's robust to missing anchors (use whichever subset is currently available, with a
  per-dimension validity mask).

### 6.2 Strategy B — Absolute multilateration *(nicer UX, phase 1.5)*
Solve the phone's **(x, y[, z])** from the 4 ranges, then test it against polygonal
zones drawn on a room map.
- Requires **anchor coordinates**. Obtain via: (a) manual entry of measured
  positions, or (b) a guided survey (place phone at known reference points / corners
  and solve anchor positions by least squares).
- Position solve: weighted **nonlinear least squares** (Gauss-Newton/Levenberg-
  Marquardt) seeded from the previous estimate; reject samples failing a residual
  gate; smooth with a constant-velocity **Kalman/EKF**.
- Zones become editable **polygons** on a 2D room canvas — much better UX than
  abstract fingerprints, and supports overlap/containment.

### 6.3 Filtering (both strategies)
- Per-anchor **EMA or 1€ filter**; reject samples with low FoM/quality or implausible
  jumps (> v_max·Δt).
- Handle stale anchors: if an anchor hasn't reported within N sweeps, mark its
  dimension invalid rather than feeding a frozen value.

---

## 7. Calibration & setup flow (UX)

1. **Add anchors:** Scan BLE, list discovered anchors, confirm each (LED blink on
   tap), assign label + ID 0–3.
2. **Room setup (Strategy B only):** Enter room dimensions or run the guided survey;
   app computes/stores anchor coordinates and shows them on a canvas.
3. **Define zones:** Walk to a spot → name it (bed/desk/window) → capture. Repeat.
   Strategy A stores fingerprints; Strategy B lets you draw/adjust polygons.
4. **Live view:** Big "current zone" banner + debug panel (per-anchor distance,
   direction arrow when present, sample rate, session/scheduler state).

---

## 8. iOS app plan (`/ios`)

- **Stack:** Swift, SwiftUI, `NearbyInteraction` + `CoreBluetooth`. Min iOS 16
  (target 18+ for the better background/Live Activity story).
- **Entitlements / Info.plist:** `NSNearbyInteractionUsageDescription`,
  `NSBluetoothAlwaysUsageDescription`; background modes (`bluetooth-central`) for P2.
- **Modules:**
  - `BLEManager` — scan, connect, accessory-config exchange (send phone's discovery
    token / shareable config to the accessory, receive accessory config back).
  - `RangingScheduler` — **round-robin** honoring the 2-session cap (§3.1); per-anchor
    dwell, rotation, and re-arm on `didInvalidateWith`/`didRemove`.
  - `Estimator` — Strategy A/B from §6.
  - `ZoneEngine`, `ZoneStore` (Codable + on-disk), `DebugViewModel`.
  - SwiftUI views: Anchors, Room/Setup, Zones, Live/Debug.
- **Phase 2:** `App Intents` to expose "current zone" + zone-enter/exit so users wire
  actions in **Shortcuts**; **Live Activity** to keep ranging alive when backgrounded
  (iOS 18.4+); optional BLE bonding for background ranging on older iOS.

---

## 9. Android app plan (`/android`)

- **Stack:** Kotlin, Jetpack Compose, `androidx.core.uwb` (Controller),
  Bluetooth GATT client for OOB. Min API 31; UWB-capable device required.
- **Modules:** mirror iOS — `BleClient`, `UwbRangingManager` (single multi-controlee
  session, no 2-session cap), `Estimator`, `ZoneEngine`, `ZoneStore`, Compose UI.
- **Differences to call out:**
  - OOB parameters are app-defined; our GATT service must carry the full FiRa config.
  - **No direction** on most devices — debug view degrades to distance-only.
  - Background ranging is allowed on most non-early-Pixel devices via a foreground
    service; Shortcuts-equivalent = Tasker intents / Quick Settings / `App Actions`.

---

## 10. Phase boundaries

| Capability | Phase 1 | Phase 2 |
|---|---|---|
| Foreground ranging to 4 anchors | ✅ | ✅ |
| Per-anchor distance + direction debug | ✅ | ✅ |
| Zone setup (fingerprint, Strategy A) | ✅ | ✅ |
| Live zone detection (foreground) | ✅ | ✅ |
| Absolute position + polygon zones (Strategy B) | optional | ✅ |
| Background detection | ❌ | ✅ (Live Activity / BLE bond) |
| Configurable actions via Shortcuts / App Intents | ❌ | ✅ |
| Android parity | basic | full |

---

## 11. Milestones

- **M0 — Repo & docs** ✅: spec, structure, decisions.
- **M1 — Anchor bring-up:** ⏳ QANI firmware compiles and links (175 KB .hex); full
  FiRa session lifecycle ported (`uwb_port_qani.c`), real AES crypto via nrf_oberon,
  bare-metal QOSAL shims. **Next:** flash to boards, verify BLE + DW3110 SPI + NI
  ranging against Apple sample app.
- **M2 — iOS single-anchor ranging:** distance + direction on screen.
- **M3 — iOS round-robin 4 anchors:** stable distance vector at ~1.5–3 Hz.
- **M4 — Zone engine (Strategy A):** capture + live detection with hysteresis.
- **M5 — Custom anchor firmware:** anchor IDs, GATT service, fast session re-arm.
- **M6 — Strategy B:** survey, multilateration, polygon zones on a room canvas.
- **M7 — Android MVP:** FiRa controlee firmware + Kotlin app to M4 parity.
- **M8 — Phase 2:** background (Live Activity / bonding) + App Intents/Shortcuts.

---

## 12. Risks & open questions

- **Session churn on iOS:** rapid teardown/re-establish of NI sessions during round-
  robin may be slow or flaky → validate dwell timing early (M3); fall back to 2
  pinned sessions + rotating the other 2 if needed.
- **Update rate vs motion:** ~1.5–3 Hz may lag fast walking → favor zone hysteresis
  over precise tracking; consider predicting through gaps with the EKF.
- **Anchor self-survey** is fiddly (NI is phone↔anchor, anchors don't easily range
  each other) → default to manual coordinate entry; treat auto-survey as stretch.
- **iPhone 15 / U2 direction quirks** for accessories → don't depend on AoA.
- **Multipath / NLOS** in a furnished room degrades distances → per-anchor FoM gating
  and generous zone radii.
- **Power/placement:** anchors need USB power; plan cabling or power banks.

---

## 13. References

- [DWM3001CDK — Qorvo](https://www.qorvo.com/products/p/DWM3001CDK)
- [Qorvo Nearby Interaction SW v3.0 release](https://forum.qorvo.com/t/qorvo-nearby-interaction-software-package-v-3-0-release/13390)
- [Apple — Nearby Interaction](https://developer.apple.com/documentation/nearbyinteraction)
- [Explore NI with third-party accessories (WWDC21)](https://developer.apple.com/videos/play/wwdc2021/10165/)
- [What's new in Nearby Interaction (WWDC22)](https://developer.apple.com/videos/play/wwdc2022/10008/)
- [NISession concurrency limits (Apple forum)](https://developer.apple.com/forums/thread/692392)
- [Android — Core UWB (Jetpack)](https://developer.android.com/jetpack/androidx/releases/core-uwb)
- [Android — UWB communication guide](https://developer.android.com/develop/connectivity/uwb)
- [NXP UWB Jetpack example](https://github.com/nxp-uwb/UWBJetpackExample)
