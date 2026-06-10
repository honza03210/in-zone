#ifndef INZONE_UWB_PORT_H
#define INZONE_UWB_PORT_H

#include <stdint.h>

/*
 * Thin port over the UWB backend. Two implementations:
 *   uwb_port_stub.c  — no radio; lets the BLE/protocol stack build and run
 *                      without the Qorvo SDK (UWB_BACKEND=stub).
 *   uwb_port_qani.c  — Qorvo QANI niq + uwbstack libs (UWB_BACKEND=qani).
 */

typedef enum {
    UWB_PORT_EVT_STARTED,  /* ranging session is live */
    UWB_PORT_EVT_STOPPED,  /* session ended (requested or dropped) */
    UWB_PORT_EVT_ERROR,
} uwb_port_evt_t;

typedef void (*uwb_port_evt_cb_t)(uwb_port_evt_t evt);

int uwb_port_init(uwb_port_evt_cb_t cb);

/* Fill `buf` with the Apple NI accessory configuration data blob.
 * In: *len = buf capacity. Out: *len = blob size. Returns 0 on success. */
int uwb_port_get_accessory_config(uint8_t *buf, uint16_t *len);

/* Start ranging using the phone's shareableConfigurationData.
 * Asynchronous; completion is signalled via UWB_PORT_EVT_STARTED. */
int uwb_port_start(const uint8_t *shareable_cfg, uint16_t len);

int uwb_port_stop(void);

#endif
