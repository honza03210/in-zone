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
src/app/    main, anchor identity (UICR), watchdog, bring-up CLI (RTT)
src/ble/    SoftDevice stack + advertising, transport & info GATT services
src/ni/     Apple NI accessory protocol state machine (transport-agnostic)
src/uwb/    uwb_port.h + stub backend + QANI backend (the only Qorvo-aware file)
config/     app_config.h overrides on top of an SDK example sdk_config.h
```

## Build

Prereqs:
- [nRF5 SDK 17.1.0](https://www.nordicsemi.com/Products/Development-software/nRF5-SDK)
  → `SDK/nRF5_SDK_17.1.0_ddde560/`
- [DW3_QM33_SDK_1.1.1](https://www.qorvo.com/) (registration-gated)
  → `SDK/DW3_QM33_SDK_1.1.1/` (only needed for QANI build)
- GNU Arm Embedded toolchain 15.2.1+, GNU Make, `nrfjprog` (nRF Command Line Tools),
  J-Link drivers (the CDK has J-Link OB — just USB)

One-time: copy `sdk_config.h` from
`<SDK>/examples/ble_peripheral/ble_app_uart/pca10100/s113/config/` into
`config/` (our `app_config.h` overrides what matters; `USE_APP_CONFIG` is
already set in the Makefile).

```sh
# 1) Stub build — no Qorvo SDK needed; BLE + protocol testable end to end
make SDK_ROOT=C:/Users/honza/in-zone/SDK/nRF5_SDK_17.1.0_ddde560

# 2) QANI build — full UWB ranging (175 KB .hex)
make SDK_ROOT=C:/Users/honza/in-zone/SDK/nRF5_SDK_17.1.0_ddde560 UWB_BACKEND=qani
```

The Makefile auto-derives the Qorvo SDK path from `SDK_ROOT` (sibling
`DW3_QM33_SDK_1.1.1` directory). GNU_GCC_ROOT defaults to the system PATH;
override if needed.

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

## Bring-up console

The same RTT channel doubles as a command console ([src/app/cli.c](src/app/cli.c)) —
type into JLinkRTTViewer/JLinkRTTClient:

| Command | What it tells you |
|---|---|
| `status` | build date, backend (stub/qani), uptime, anchor id/label, BLE + NI state, last range |
| `spi` | reads the DW3110 `DEV_ID` over bit-banged SPI — `0xDECA03xx OK` proves the UWB chip is wired and powered (pulses RSTN and retries once if the first read fails). Refused while a NI session owns the bus. |
| `uicr` | raw provisioning registers + decoded id/label — verifies `provision.ps1` without a reflash |
| `led <boot\|adv\|conn\|range\|err\|id>` | force an LED pattern to check pins |
| `reset` | reboot the MCU |

The console is polled from the main loop, which sleeps between events —
while advertising, keystrokes are picked up within ~100 ms (the BLE
advertising interval), worst case 1 s (the CLI's uptime tick).

## Bring-up sequence (matches spec milestones M1–M2)

1. **Stock sanity check:** flash Qorvo's prebuilt QANI `.hex` and verify
   ranging with Qorvo's iOS demo app — proves hardware + phone.
2. **Stub build:** flash ours; run `status` and `spi` on the bring-up
   console (boot + DW3110 wiring), then verify advertising (`InZone-Ax`),
   identify blink, and the message exchange against the In-Zone iOS app
   (the phone will report an invalid NI config — expected, see
   `uwb_port_stub.c`).
3. **QANI build:** ✅ compiles and links (175 KB). Full FiRa session lifecycle
   in `uwb_port_qani.c`, real AES crypto via nrf_oberon, bare-metal QOSAL
   shims. **Next:** flash to boards, verify BLE advertising + DW3110 SPI
   probe + NI ranging against the iOS app.
