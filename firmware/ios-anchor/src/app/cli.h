#ifndef INZONE_CLI_H
#define INZONE_CLI_H

/*
 * Bring-up console over SEGGER RTT (channel 0, shared with NRF_LOG).
 * Connect with JLinkRTTViewer / JLinkRTTClient and type `help`.
 *
 * Exists for hardware bring-up: verifying boot, BLE advertising, the
 * DW3110 SPI link, and UICR provisioning without a debugger session.
 */

void cli_init(void);

/* Call from the main loop; consumes pending RTT input, runs commands. */
void cli_poll(void);

#endif
