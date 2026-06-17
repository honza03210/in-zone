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
responds. QANI `qspi_transceive` deadlock root-caused and patched (see
`firmware/patches/README.md`): the DW bring-up runs with `PRIMASK=1`
(qirq_lock `cpsid i`), so the SPIM `END` interrupt that sets
`txf_is_finished` never fires — confirmed via SWD halt (transfer done,
IRQ pending+masked, PC stuck at the wait). Fix = poll the END event in
the blocking branch instead of relying on the IRQ. Transfers now
complete, **but** QANI init still doesn't finish — the DW driver then
**QANI now boots on hardware (2026-06-16):** completes the full uwb-stack
init, drives the DW3110, and advertises with no fault (verified via SWD:
`g_fault`=0, SPIM cycling, advertising LED). Three bare-metal port bugs
fixed (see `firmware/patches/README.md` for the SWD traces):
1. `qirq_lock` used `cpsid i` (PRIMASK), masking the SPIM3 completion IRQ
   nrfx needs → SPI deadlock. Reworked to raise BASEPRI **mask pri >= 5**
   (keeps SPIM3 pri3 AND the SoftDevice incl. SVCall pri4 live; masking
   pri4 made sd_*() calls fault). FreeRTOS model.
2. `l1_config` persist sections were orphans landing in .rodata (~0x47E90);
   its runtime flash page-erase wiped app code → HardFault calling an
   erased handler. Pinned them to dedicated flash pages (0x7D000/0x7E000)
   in the linker.
3. our `qworkqueue_init` shim had the WRONG signature vs qworkqueue.h
   (`qworkqueue_init(handler, priv)` returning a handle) → it wrote
   through the handler fn-ptr → unaligned fault. Rewrote the workqueue
   shim to match the real API.
Also: qmalloc heap 8K→50K (matches Qorvo), a real HardFault_Handler in
main.c that captures the fault frame to globals (g_fault/g_cfsr) for SWD,
and the qspi.c END-poll patch (now belt-and-suspenders). Board holds QANI.

**Blocker (2026-06-17): firmware resets when ranging starts.** First
end-to-end test: the iOS NI handshake fully completes (`init=cfgRx=sess=shr=
conf=1`), the anchor enters RANGING (one blue blink), then the **SoftDevice
asserts** (`NRF_FAULT_ID_SD_ASSERT`) inside `uwbmac_start()` and the watchdog
reboots. Reproduces even with no BLE connection, so it's a SoftDevice/UWB-MAC
coexistence problem in the bare-metal QOSAL port, not BLE timing. Ruled out:
IRQ priorities, all SD-reserved peripherals, IRQ masking, stack overflow,
build config, the workqueue model (deferring it didn't help). Full diagnosis
+ recommended fix (port QANI to FreeRTOS, Qorvo's supported SD-coexistence
model) in `firmware/patches/README.md`. In-tree diagnostic changes:
`STEP()` logging + deferred workqueue in qosal_shim.c / uwb_port_qani.c.

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
