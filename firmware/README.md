# Anchor firmware — DWM3001CDK

Firmware for the 4 anchors (nRF52833 host + DW3110 UWB). Plan and
architecture: [docs/SPECIFICATION.md §5](../docs/SPECIFICATION.md).

| Path | Contents |
|---|---|
| [`ios-anchor/`](ios-anchor/) | **iOS / Apple Nearby Interaction build** (current) |
| [`scripts/`](scripts/) | Flash, UICR provisioning, and readback (PowerShell, `nrfjprog`) |
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

## Scripts

| Script | Purpose |
|---|---|
| `provision.ps1` | Write anchor ID (0–3) + label to UICR on one board |
| `provision_all.ps1` | Walk through all 4 boards, provisioning each in sequence |
| `read_uicr.ps1` | Read back and display what's provisioned on a connected board |
| `flash.ps1` | Flash SoftDevice + application hex to a board |

```powershell
# Provision all 4 with default labels (door, window, desk, bed):
cd firmware\scripts
.\provision_all.ps1

# Or provision one at a time:
.\provision.ps1 -AnchorId 2 -Label "window"

# Verify what's on a board:
.\read_uicr.ps1

# Flash firmware:
.\flash.ps1 -Hex ..\ios-anchor\_build\nrf52833_xxaa.hex `
            -SoftDevice C:\nRF5_SDK_17.1.0\components\softdevice\s113\hex\s113_nrf52_7.2.0_softdevice.hex
```

Start here: [ios-anchor/README.md](ios-anchor/README.md).
