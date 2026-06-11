# Anchor firmware — DWM3001CDK

Firmware for the 4 anchors (nRF52833 host + DW3110 UWB). Plan and
architecture: [docs/SPECIFICATION.md §5](../docs/SPECIFICATION.md).

| Path | Contents |
|---|---|
| [`ios-anchor/`](ios-anchor/) | **iOS / Apple Nearby Interaction build** (current) |
| [`scripts/`](scripts/) | Flash + UICR provisioning (PowerShell, `nrfjprog`) |
| [`vendor/`](vendor/) | Drop zone for the license-gated Qorvo QANI package (git-ignored) |
| `android-anchor/` | FiRa controlee build for Android — planned (spec §3.4, M7) |

## Design in one paragraph

All application logic — BLE stack, GATT services, Apple NI accessory
protocol, identity, LEDs, watchdog — is our code and builds standalone
against the free nRF5 SDK with a **stub UWB backend** (`UWB_BACKEND=stub`).
Qorvo's binary UWB libraries (registration-gated, non-redistributable) are
isolated behind a 6-function port layer
([`uwb_port.h`](ios-anchor/src/uwb/uwb_port.h)); switching to
`UWB_BACKEND=qani` links the uwbstack_bundle + niq library + nrf_oberon
crypto for real ranging. The QANI integration files:
- `uwb_port_qani.c` — full FiRa session lifecycle (start/stop/params/callbacks)
- `qosal_shim.c` — bare-metal replacements for QOSAL/FreeRTOS primitives
- `mcps_crypto_stub.c` — real AES crypto (CMAC, CCM*, ECB) via nrf_oberon + SoftDevice TRNG
- `qplatform_common_wrap.c`, `qpwr_qm33_wrap.c` — basename-collision wrappers

**Current status:** Both builds compile and link. The QANI build produces a
175 KB .hex. Not yet flashed/tested on hardware.

Dual-mode (iOS+Android auto-detect) is the agreed future direction; the
mode characteristic in the anchor-info service and the per-connection
protocol selection are designed with that in mind.

Start here: [ios-anchor/README.md](ios-anchor/README.md).
