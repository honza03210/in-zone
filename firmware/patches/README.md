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
why the chip won't advance to the expected state (candidate: clock/XTAL
or IDLE_RC not reached, or a config-verify mismatch). A known-good run of
Qorvo's stock DWM3001CDK firmware would give a reference init sequence to
diff against.
