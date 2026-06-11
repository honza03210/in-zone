# In-Zone — Claude Code project notes

## What this is

UWB room zone detection: 4× Qorvo DWM3001CDK anchors + iPhone 15 (primary) + Android (secondary).
Full spec: `docs/SPECIFICATION.md`.

## Current state (2026-06-10)

Firmware (`firmware/ios-anchor/`) builds and links for both backends:

- **Stub build** (`make SDK_ROOT=...`): BLE + NI protocol, no UWB hardware.
- **QANI build** (`make SDK_ROOT=... UWB_BACKEND=qani`): Full UWB ranging via
  Qorvo uwbstack_bundle + niq library + nrf_oberon crypto. Produces 175 KB .hex.

The QANI build includes a complete FiRa session lifecycle port (uwb_port_qani.c)
from Qorvo's reference firmware. Not yet tested on hardware.

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

- Flash firmware to DWM3001CDK boards, verify boot + BLE advertising + DW3110 SPI probe
- Build the iOS app (NISession + CoreBluetooth)
- End-to-end: iPhone ↔ anchor NI ranging
