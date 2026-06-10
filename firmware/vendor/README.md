# Vendor packages (not committed)

The full UWB build links against Qorvo's binary libraries, which are
license-gated and must not be committed to this repo. Download once and
unpack here.

## Qorvo QANI package → `vendor/qani/`

1. Create a free account at [qorvo.com](https://www.qorvo.com) and open the
   [DWM3001CDK product page](https://www.qorvo.com/products/p/DWM3001CDK).
2. Download **"Qorvo Nearby Interaction" (QANI) software package** v3.x
   (named like `DWM3001CDK_QANI_…` / "Nearby Interaction software").
3. Unpack so this layout exists:

   ```
   vendor/qani/
     Apps/...            # Qorvo reference apps (incl. ble_niq.c — see below)
     Libs/niq/           # Apple NI accessory lib (libniq-m4-*.a + headers)
     Libs/uwbstack/      # UWB MAC stack (binary)
     ...
   ```

   Layout differs slightly between releases — adjust `QANI_ROOT` paths in
   [ios-anchor/Makefile](../ios-anchor/Makefile) to match what you got.

## Integration checklist (one-time, ~30 min)

The only file calling Qorvo APIs is
[`ios-anchor/src/uwb/uwb_port_qani.c`](../ios-anchor/src/uwb/uwb_port_qani.c).
Function names are confirmed from QANI 3.x, but signatures vary per release:

1. Open `Apps/.../ble_niq.c` in the package you downloaded.
2. For every call site tagged `VERIFY(...)` in `uwb_port_qani.c`, copy the
   exact signature/usage from the reference app (`niq_init`,
   `niq_populate_accessory_uwb_config_data`, `niq_configure_and_start_uwb`,
   `niq_stop_uwb`, plus any required UWB MAC init the reference app does
   before `niq_init`).
3. Add the package's lib files + include dirs to the `UWB_BACKEND=qani`
   section of the Makefile.
4. `make UWB_BACKEND=qani SDK_ROOT=...`

Until then, `UWB_BACKEND=stub` (default) builds and runs with no vendor
code — BLE, identity, and the NI message exchange all work; only actual
UWB ranging is faked.
