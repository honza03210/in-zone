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

### Next: HardFault in nrf_balloc_init (open, with BASEPRI >= 5)

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
