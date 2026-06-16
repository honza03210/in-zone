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
interrupts masked. **Not yet sufficient for full QANI bring-up:** after this,
the DW driver progresses but appears to loop doing SPI reads during init
(likely polling a chip-ready status that never sets — the DW3110 boots
asleep, see the stub `spi` wakeup finding). That is the next thing to debug.
