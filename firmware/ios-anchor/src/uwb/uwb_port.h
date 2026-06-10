#ifndef INZONE_UWB_PORT_H
#define INZONE_UWB_PORT_H

#include <stdint.h>
#include <stdbool.h>

/*
 * Thin port over the UWB backend. Two implementations:
 *   uwb_port_stub.c  — no radio; lets the BLE/protocol stack build and run
 *                      without the Qorvo SDK (UWB_BACKEND=stub).
 *   uwb_port_qani.c  — Qorvo QANI niq + uwbstack libs (UWB_BACKEND=qani).
 */

typedef enum {
    UWB_PORT_EVT_STARTED,  /* ranging session is live */
    UWB_PORT_EVT_STOPPED,  /* session ended (requested or dropped) */
    UWB_PORT_EVT_RANGE,    /* new ranging measurement available */
    UWB_PORT_EVT_ERROR,
} uwb_port_evt_t;

typedef struct {
    int32_t  distance_cm;
    int16_t  azimuth_deg_q7;   /* azimuth angle * 128, or INT16_MIN if N/A */
    int16_t  elevation_deg_q7; /* elevation angle * 128, or INT16_MIN if N/A */
    uint8_t  aoa_fom;          /* figure of merit 0-100, 0 = unavailable */
    bool     valid;
} uwb_port_range_t;

typedef void (*uwb_port_evt_cb_t)(uwb_port_evt_t evt);

int uwb_port_init(uwb_port_evt_cb_t cb);

/* Fill `buf` with the Apple NI accessory configuration data blob.
 * In: *len = buf capacity. Out: *len = blob size. Returns 0 on success. */
int uwb_port_get_accessory_config(uint8_t *buf, uint16_t *len);

/* Start ranging using the phone's shareableConfigurationData.
 * Asynchronous; completion is signalled via UWB_PORT_EVT_STARTED. */
int uwb_port_start(const uint8_t *shareable_cfg, uint16_t len);

int uwb_port_stop(void);

/* Call from the main loop to process pending UWB MAC events.
 * Returns true if there was work to do. */
bool uwb_port_poll(void);

/* Read the most recent ranging result (valid after UWB_PORT_EVT_RANGE). */
const uwb_port_range_t *uwb_port_last_range(void);

#endif
