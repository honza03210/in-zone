# In-Zone anchor firmware — iOS (Apple Nearby Interaction) build

Firmware for the 4 DWM3001CDK anchors when used with the iPhone app.
Architecture and rationale: [docs/SPECIFICATION.md §5](../../docs/SPECIFICATION.md).

## What it does

- Boots, reads its **anchor ID (0–3) + label** from UICR (provisioned once
  via [scripts/provision.ps1](../scripts/provision.ps1)), advertises as
  `InZone-A<id>`.
- Phone connects and runs the **Apple NI accessory protocol** over the
  In-Zone transport service (UUID base `49A7xxxx-9A91-4B5C-8E3F-2D1C7A6B5E40`):
  `INITIALIZE → accessory config → CONFIGURE (shareable config) → UWB ranging`.
- On disconnect: UWB session torn down, **advertising resumes immediately** —
  required by the phone's round-robin scheduler (iOS allows only 2 concurrent
  NI sessions, so the app cycles anchors).
- Extras: anchor-info GATT service (id/label/fw/mode + **identify blink**),
  LED status, 8 s hardware watchdog.

### LED legend

| LED | Meaning |
|---|---|
| Green D9 blink / solid | advertising / connected |
| Blue D10 blink | UWB ranging active |
| Red D11 solid | error |
| Red D12 blink | "identify" triggered from the app |

## Layout

```
src/app/    main, anchor identity (UICR), watchdog
src/ble/    SoftDevice stack + advertising, transport & info GATT services
src/ni/     Apple NI accessory protocol state machine (transport-agnostic)
src/uwb/    uwb_port.h + stub backend + QANI backend (the only Qorvo-aware file)
config/     app_config.h overrides on top of an SDK example sdk_config.h
```

## Build

Prereqs: [nRF5 SDK 17.1.0](https://www.nordicsemi.com/Products/Development-software/nRF5-SDK),
GNU Arm Embedded toolchain 10.3+, GNU make, `nrfjprog` (nRF Command Line Tools),
J-Link drivers (the CDK has J-Link OB — just USB).

One-time: copy `sdk_config.h` from
`<SDK>/examples/ble_peripheral/ble_app_uart/pca10100/s113/config/` into
`config/` (our `app_config.h` overrides what matters; `USE_APP_CONFIG` is
already set in the Makefile). Set the toolchain path in
`<SDK>/components/toolchain/gcc/Makefile.windows`.

```sh
# 1) Stub build — no Qorvo SDK needed; BLE + protocol testable end to end
make SDK_ROOT=C:/nRF5_SDK_17.1.0_ddde560

# 2) Full UWB build — after vendor setup, see ../vendor/README.md
make SDK_ROOT=C:/nRF5_SDK_17.1.0_ddde560 UWB_BACKEND=qani
```

## Flash + provision each anchor (×4)

```powershell
make SDK_ROOT=... flash_softdevice   # once per board (S113 7.2.0)
make SDK_ROOT=... flash              # the app
cd ..\scripts
.\provision.ps1 -AnchorId 0 -Label "door"   # 0..3, unique per board
```

Logs stream over RTT: `make rtt` or `JLinkRTTViewer`, target `NRF52833_XXAA`.
First boot logs `SoftDevice RAM start 0x…` — if it differs from the linker
script's RAM ORIGIN, adjust [inzone_anchor_nrf52833.ld](inzone_anchor_nrf52833.ld).

## Bring-up sequence (matches spec milestones M1–M2)

1. **Stock sanity check:** flash Qorvo's prebuilt QANI `.hex` and verify
   ranging with Qorvo's iOS demo app — proves hardware + phone.
2. **Stub build:** flash ours; verify advertising (`InZone-Ax`), identify
   blink, and the message exchange against the In-Zone iOS app (the phone
   will report an invalid NI config — expected, see `uwb_port_stub.c`).
3. **QANI build:** wire `uwb_port_qani.c` (see [vendor/README.md](../vendor/README.md)),
   verify real distance/direction in the iOS app debug view.
