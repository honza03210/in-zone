# In-Zone — Claude Code project notes

## What this is

UWB room zone detection: 4× Qorvo DWM3001CDK anchors + iPhone 15 (primary) + Android (secondary).
Full spec: `docs/SPECIFICATION.md`.

## Current state (2026-06-11)

Firmware (`firmware/ios-anchor/`) builds and links for both backends:

- **Stub build** (`make SDK_ROOT=...`): BLE + NI protocol, no UWB hardware.
- **QANI build** (`make SDK_ROOT=... UWB_BACKEND=qani`): Full UWB ranging via
  Qorvo uwbstack_bundle + niq library + nrf_oberon crypto. Produces 175 KB .hex.

The QANI build includes a complete FiRa session lifecycle port (uwb_port_qani.c)
from Qorvo's reference firmware. Not yet tested on hardware.

A bring-up console (src/app/cli.c) runs over the RTT log channel:
`status` / `spi` (bit-banged DW3110 DEV_ID probe) / `uicr` / `led` / `reset`.

**Hardware bring-up (2026-06-16):** stub build verified on a real DWM3001CDK
— boots, SoftDevice + BLE advertising up, and the `spi` probe reads
`DEV_ID=0xDECA0302 OK`. Gotcha found in the process: the DW3110 **CS is on
P1.06** (port 1), not P0.06 — only CS/WU/IRQ are on port 1, the other SPI
lines are port 0 (see Qorvo `uwb_stack_llhw.cmake` / our Makefile CFLAGS).
The DW3110 also boots **asleep**; a >400 µs CS-low pulse wakes it before SPI
responds. QANI build still hangs in `qspi_transceive` (QOSAL/SPIM completion
shim) — that's the next firmware problem, and the chip is confirmed healthy.

iOS app (`ios/InZone/`, xcodegen) is feature-complete for first hardware
tests: BLE scan/connect, round-robin NI ranging (2-session cap), zone
capture + fingerprint detection, 2D room map with trilateration, simulator
mode (auto-active on iOS Simulator). CI on GitHub Actions
(`.github/workflows/ios.yml`) builds and runs the 72-test suite on every
push touching `ios/**` — green as of 2026-06-11.
Repo: https://github.com/honza03210/in-zone

## Build

Requires two SDKs (git-ignored via `SDK/` in `.gitignore`):
- `SDK/nRF5_SDK_17.1.0_ddde560/` — free Nordic SDK
- `SDK/DW3_QM33_SDK_1.1.1/` — registration-gated Qorvo SDK

Toolchain: GNU Arm Embedded 15.2.1 at
`C:\Program Files\Arm\GNU Toolchain mingw-w64-x86_64-arm-none-eabi\bin\`

```sh
cd firmware/ios-anchor
make SDK_ROOT=C:/Users/honza/in-zone/SDK/nRF5_SDK_17.1.0_ddde560 UWB_BACKEND=qani
```

## Key architecture decisions

- **uwb_port.h** is the abstraction boundary: 6 functions, two implementations
  (stub + qani). All Qorvo SDK awareness is isolated in uwb_port_qani.c.
- **Bare-metal QOSAL shims** (qosal_shim.c) replace FreeRTOS for the
  pre-compiled uwbstack_bundle. Bump allocator, inline workqueue, flag-based
  signals. If runtime issues arise, the fix is adding FreeRTOS.
- **nrf_oberon** provides real AES crypto (CMAC, CCM*, CBC/ECB) via a
  precompiled Cortex-M4 library. RNG uses SoftDevice hardware TRNG.
- **apply_old_config.h** in the nRF5 SDK rewrites NRFX_* macros from legacy
  names. SPI0 is enabled as a dummy so the macro expression evaluates true
  (it only checks instances 0-2, not SPI3 which we actually use).
- nRF5 SDK Makefile.common uses `notdir` for .o names — duplicate basenames
  (qplatform.c, qpwr.c) need wrapper files with unique names.

## Gotchas

- `PASS_LINKER_INPUT_VIA_FILE` must be 0 — Make 4.4.1 corrupts paths in the
  linker response file (strips slashes, mangles drive letters).
- l1_config.c / l1_config_custom.c are already in the uwbstack_bundle .a —
  do NOT compile them from source (they need a generated l1_config_keys.h).
- The `config/sdk_config.h` is a copy from the nRF5 SDK BLE UART example;
  `app_config.h` overrides what matters. QANI peripheral enables are in
  CFLAGS (legacy names), not sdk_config.h.

## Next milestones

- Flash firmware to DWM3001CDK boards; use the RTT console (`status`, `spi`,
  `uicr`) to verify boot + BLE advertising + DW3110 SPI probe
- Compile the iOS app on a Mac, run on iPhone 15 (CI already verifies it builds)
- End-to-end: iPhone ↔ anchor NI ranging
