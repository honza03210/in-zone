# Vendored SDK patches

The Qorvo `DW3_QM33_SDK_1.1.1` lives under `SDK/` and is git-ignored, so
local fixes to its source are recorded here and must be re-applied after a
fresh SDK extraction.

## qspi-poll-completion

**File:** `SDK/DW3_QM33_SDK_1.1.1/SDK/Firmware/Libs/uwb-stack/libs/qhal/src/nrfx/qspi.c`
**Function:** `qspi_transceive`, the master blocking-wait branch (`if (!spi->handler)`).

**Why:** Blocking SPI completion is signalled by the SPIM `END` interrupt
(`qspi_generic_handler_master` sets `txf_is_finished`). In our bare-metal
port the DW3110 bring-up runs with interrupts masked (`PRIMASK=1`, set by
`qirq_lock`'s `cpsid i`), so that interrupt can never fire and the original
`while (spi->txf_is_finished == false) ;` spins forever. Confirmed on
hardware: transfer completes (`ENDRX/ENDTX=1`, `RXD.AMOUNT=4`), SPIM3 IRQ
latches pending in the NVIC, but `PRIMASK=1` blocks it; PC stuck at the wait.

**Change:** in the `#if NRFX_SPIM_ENABLED` blocking branch, exit on either
the flag (IRQ ran, interrupts were enabled) or the `END` event (IRQ masked),
then finish the transfer manually if the IRQ did not:

```c
while (!spi->txf_is_finished &&
       !nrf_spim_event_check(spi->type.spim.p_reg, NRF_SPIM_EVENT_END))
    ;
if (!spi->txf_is_finished) {
    nrf_spim_event_clear(spi->type.spim.p_reg, NRF_SPIM_EVENT_END);
    spi->txf_is_finished = true;
    nrf_spim_disable(spi->type.spim.p_reg);
}
```

This resolves the single-transfer deadlock — transfers now complete with
interrupts masked.

### Remaining QANI init loop (open)

After the poll fix, QANI still doesn't finish booting — it loops in
`fira_uwb_mcps_init` doing SPI during DW3110 bring-up. Hardware findings
from SWD halts (so the next session doesn't re-derive them):

- **Not a deadlock anymore:** SPIM state cycles (ENABLE 7↔0), transfers
  complete. PC is ~always in `qspi_transceive` only because that's the
  hottest code in a higher-level retry loop.
- **CS is fine:** P1.06 is an output and driven low (asserted) during
  transfers (`P1.DIR` bit6=1, `P1.OUT` bit6=0). Earlier CS-port bug was
  the stub probe only; the QANI/Makefile CS port was always correct.
- **Pins/ports correct, IRQ priority 3 (SD-compatible), delays real**
  (`qtime_*` are busy-loops, ~4x long if anything, not no-ops).
- **Chip responds at least partially:** an RX buffer once held `DE` (top
  byte of DEV_ID 0xDECA0302), so the probe got past DEV_ID; but most
  reads return zeros.
- **The loop's SPI transaction is a register WRITE** (TX header byte
  `0xD6...`), i.e. an init step being retried, not a plain status poll.

Next lead: identify the DW3000 init step that retries (decode the `0xD6`
register target; trace `llhw_init`/`dwt_initialise`/`dwt_configure`), and
why the chip won't advance to the expected state.

### Reference test: board is GOOD (2026-06-16)

Flashed Qorvo's prebuilt `SDK/Binaries/DWM3001CDK/DWM3001CDK-CLI-FreeRTOS.hex`
(`nrfjprog --program ... --chiperase --reset`) and inspected over SWD:
`SPIM3.ENABLE=0` steadily, PC busy-polling in its own loop (UARTE0/1 also
off — the Qorvo CLI talks over the nRF52833 **native USB**, a separate
connector, which is why the J-Link VCOM COM4 was silent). So Qorvo's
firmware **completes DW3110 init** on this exact board and goes idle.

Conclusion: **the hardware is fine; our QANI hang is a bug in our
bare-metal port, not the board or chip.** The most likely culprit is the
QOSAL layer differing from Qorvo's FreeRTOS: our `qirq_lock` masks all
interrupts via `PRIMASK` (`cpsid i`) — FreeRTOS uses BASEPRI and keeps
high-priority IRQs live. If a broad/long `PRIMASK` critical section wraps
DW init, anything interrupt-driven the driver needs (timers, the DW IRQ
on P1.02/GPIOTE) is dead. Next: check whether PRIMASK is held across init
(not just during one SPI xfer) and whether the DW IRQ is serviced.

### qirq_lock PRIMASK → BASEPRI (fixed, in our tree: src/uwb/qosal_shim.c)

Root cause of the SPI loop confirmed: `qirq_lock` used `cpsid i` (PRIMASK),
masking ALL interrupts — including the SPIM3 completion IRQ (pri 3). nrfx_spim
is interrupt-driven and clears its `transfer_in_progress` state only in that
IRQ, so with it masked the first transfer never completes and the next returns
BUSY → the init loop. (The qspi.c END-poll patch alone can't fix this: nrfx's
own state never clears.) Fix: `qirq_lock`/`qirq_disable` now raise BASEPRI to
mask priority >= 4 (covers DW pri7, GPIOTE pri6, timers, SD SWI pri4) while
leaving SPIM3 (pri3) and SD timing-critical (0/1) live — the FreeRTOS model.

Verified on hardware: SPIM goes idle, the init **advances past the SPI loop**.

### BASEPRI threshold MUST be >= 5 (not >= 4)

Settled the threshold: mask priority **>= 5** (BASEPRI 0xA0). The SoftDevice's
**SVCall is priority 4** — masking >= 4 makes any `sd_*()` call inside a
qirq_lock HardFault (the SVC can't be taken). The uwb stack's `qflash_write`
calls `sd_flash_page_erase` from inside a lock, so at >= 4 it faulted in
`sd_flash_page_erase` (precise PC, FP exception frame). At >= 5, SVCall (4),
the SPIM3 IRQ (3) and SD timing-critical (0/1) all stay live, masking only the
stack's own IRQs (DW 7, GPIOTE 6, timers). (An earlier "nrf_balloc_init"
reading at >= 4 was a mis-read from the wrong MSP — the real frame is an FP
frame at a different SP; always read MSP from regs.)

### RESOLVED: l1_config erased app code; qworkqueue signature mismatch

A clean HardFault_Handler (main.c, captures the frame to g_fault/g_cfsr)
gave reliable traces and revealed two more bugs after the BASEPRI fix:

1. **l1_config flash section overlap.** Fault was the SoftDevice event
   dispatcher (SWI2 / nrf_sdh_evts_poll) calling a handler at 0xFFFFFFFE
   (erased flash). Cause: `l1_config` persists config via sd_flash and
   page-erases the page holding its storage; the precompiled bundle emits
   `.l1_config_persist_storage` / `..._sha256` as ORPHAN sections that
   landed in .rodata at ~0x47E90, so the erase wiped app code. Fix: pin
   both sections to dedicated 4 KB flash pages (0x7D000 / 0x7E000) in
   inzone_anchor_nrf52833.ld. NOTE: the linker script is not a make
   prerequisite — `rm _build/*.out` to force a relink after editing it.

2. **qworkqueue shim signature mismatch.** Next fault was an UNALIGNED
   UsageFault in our qworkqueue_init (qosal_shim.c) writing through arg0.
   The real API (qosal/include/qworkqueue.h) is
   `struct qworkqueue *qworkqueue_init(qwork_func handler, void *priv)` —
   our stub took `(struct qwork*, func, arg)`, so the stack's
   `qworkqueue_init(handler, priv)` made us write through the handler
   fn-ptr. Rewrote the workqueue shim (init/schedule/cancel) to match;
   schedule runs the handler inline (bare-metal, no task).

Result: QANI boots fully, drives the DW3110, advertises, no fault.

Open: end-to-end NI ranging with the iPhone (needs the Mac-built app),
and confirming the "QANI backend initialised" niq log over RTT. Also note
the inline qworkqueue_schedule_work may need deferral-to-main-loop if a
work item is scheduled from an ISR and is heavy/re-entrant.

#### (historical) earlier mis-diagnosis

With the threshold correct, boot now advances further but still HardFaults
(precise PC = `nrf_balloc_init` nrf_balloc.c:279, `p_pool->p_cb->...`), with
stacked R0 == LR == 0x00047DFC (a rodata addr) — a corrupted call, not a
normal init. `s_heap_used == 0` at the fault, so it is NOT the bump allocator
(qmalloc untouched); raising HEAP_SIZE 8K → 50K (to match Qorvo's
configTOTAL_HEAP_SIZE, needed later anyway) did not change it. This is a
distinct memory-corruption bug in early `fira_uwb_mcps_init`
(qplatform_init / l1_config_init, before uwbmac allocates). Next: trace the
caller of nrf_balloc_init (which pool? why R0 is a rodata literal), and the
l1_config / qflash flash-config path on a chip-erased board (no stored
l1_config → it writes defaults via sd_flash). Consider whether a dedicated
flash region for l1_config is reserved in the linker.

To re-run the reference: `nrfjprog -f nrf52 --program \
SDK/.../Binaries/DWM3001CDK/DWM3001CDK-CLI-FreeRTOS.hex --chiperase --reset`
(then restore ours: rebuild stub/qani + flash SoftDevice + app). To drive
the Qorvo CLI interactively, plug a cable into the board's nRF USB
connector — a new COM port appears for it.

## OPEN: SoftDevice assert in uwbmac_start when ranging starts (2026-06-17)

End-to-end NI ranging was attempted for the first time (iOS app built and
installed via TestFlight). **The iOS-side handshake is fully working** — the
phone completes INITIALIZE → accessory config → shareable config → CONFIGURE
(Live→Debug shows `init=1 cfgRx=1 sess=1 shr=1 conf=1`). The fix on the app
side was using `NINearbyAccessoryConfiguration(data:)` instead of the iOS 16
`init(accessoryData:bluetoothPeerIdentifier:)` variant — Qorvo's niq emits a
v1.0 ("Developer Preview") accessory config, which the `accessoryData:`
initializer silently rejects (no shareable config, no error).

**The firmware crashes the instant ranging starts.** The anchor receives the
CONFIGURE, enters the RANGING LED state (one blue blink), then resets.

### Root cause located (but not yet fixed)

Caught live over SWD with GDB (break at `app_error_fault_handler`):

- It is a **SoftDevice assert**: `id=1` (`NRF_FAULT_ID_SD_ASSERT`), `pc` inside
  the SoftDevice flash (`0x12214` in S113 7.2.0), `CFSR=0` (no bus/usage fault).
  The board reboots because the assert handler spins with IRQs off and the 8 s
  watchdog fires (it is *not* hitting our HardFault_Handler).
- Flushed step-logging through `fira_session_start` (the `STEP()` macro in
  `uwb_port_qani.c`) pins the trigger to **`uwbmac_start()`** — `pre uwbmac_start`
  is the last marker; `pre start_session` never prints.
- Reproduces **with no BLE connection at all** — a diagnostic build that
  auto-starts ranging 4 s after boot, phone never connected, asserts every
  cycle. So it is **not** a BLE radio-timing issue; merely having the
  SoftDevice *enabled* is incompatible with the MAC bring-up.
- GDB stack walk at the assert: MSP is **shallow** (~296 B used), so
  `uwbmac_start` had already largely unwound — the assert is **asynchronous**,
  firing from the MAC's freshly-enabled interrupt processing just after
  bring-up. The most recent (stale) frame was **`ocrypto_aes_ccm_decrypt`**
  (the secure-ranging STS crypto), so the STS path is active at the failure.

### Ruled out (with evidence)

- **Interrupt priorities** — all SoftDevice-safe: UWB SPI=3, GPIOTE=6, RTC2=7,
  app_timer=6. None are SD-reserved (0/1/4).
- **Every SD-reserved peripheral** — disassembly scan for literal base
  addresses found ZERO access to ECB, CCM/AAR, RADIO, TIMER0, RTC0, PPI, RNG on
  the ranging path. TEMP is touched only in `SystemInit` (boot errata, before
  the SoftDevice is enabled). The DW3110 reads its *own* temperature over SPI
  (`dwt_readtempvbat`), not `NRF_TEMP`.
- **Interrupt masking** — only 6 `cpsid`/`cpsie` sites in the whole image, all
  in `app_error_fault_handler` + `app_util_critical_region_*`. The precompiled
  `uwbmac` bundle has **no** PRIMASK at all; `qirq_lock` uses BASEPRI (≥5).
- **Build config** — `SOFTDEVICE_PRESENT`, `S113`, `RTC2_ENABLED` all defined,
  so SDK `CRITICAL_REGION_ENTER` uses the SD-aware `sd_nvic` path.
- **Stack overflow** — stack was shallow at the assert, not deep.
- **The workqueue / threading model** — see below; disproven.
- **Crypto glue** — `mcps_crypto_stub.c`'s CCM call matches nrf_oberon's
  signature exactly (pt, tag/tag_len, ct/ct_len, key/size, nonce(13)/n_len,
  aa/aa_len); oberon is pure software.

### Attempted fix (option 2): deferred workqueue — did NOT fix it

`qworkqueue_schedule_work` used to run the handler **inline**, so MAC work that
scheduled more work recursed on the caller's stack — the hypothesis was that
this recursed during `uwbmac_start`. Reworked it (in tree) to defer: schedule
marks the item pending; `qworkqueue_run_pending()` drains them iteratively from
the main loop (`uwb_port_poll`) and cooperatively from blocking waits
(`qsignal_wait`), with a depth guard. This matches the FreeRTOS worker-task
model and is a reasonable keeper, **but it did not fix the assert** — and the
logs proved why: only 2 workqueues are ever created and **zero run** before the
assert, so the workqueue was never on the crash path. (Changes live in
`qosal_shim.c` + `uwb_port_qani.c`, alongside the `STEP()` diagnostics in
`uwb_port_qani.c`.)

### Assessment & next step

This is a subtle SoftDevice timing/protocol assertion (or memory corruption)
deep inside the precompiled UWB MAC's interrupt-driven bring-up — not
resolvable from outside without SoftDevice symbols. It is exactly the class of
issue the **FreeRTOS** integration is built to handle: Qorvo's QANI reference
for the DWM3001CDK *does* run with a SoftDevice (app at flash `0x1c000`, RAM
reserved for the SD, `#ifdef SOFTDEVICE_PRESENT`) — **but on FreeRTOS, not the
bare-metal QOSAL shims**. The cheap, high-yield diagnostics are exhausted.

Recommended path forward, in order:
1. **Port the QANI build to FreeRTOS** (Qorvo's supported SD-coexistence model).
   Highest effort, highest probability of working.
2. **Nordic DevZone**: ask them to decode the S113 7.2.0 assert at `pc=0x12214`
   — that maps to the specific violated constraint and may yield a small fix.
3. A DWT data-watchpoint on the SoftDevice RAM boundary (~`0x20002600`) to catch
   a wild write, if the memory-corruption angle is pursued before FreeRTOS.

How to reproduce the capture: build+flash QANI, run `JLinkRTTLogger` (RTT chan
0) for the `step:` markers, or `JLinkGDBServerCL` + `arm-none-eabi-gdb` with a
breakpoint at `app_error_fault_handler` and `x/320xw $msp`, then resolve the
app-range (`0x1c000`–`0x48738`) return addresses with `addr2line`.
