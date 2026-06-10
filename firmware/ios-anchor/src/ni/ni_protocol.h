#ifndef INZONE_NI_PROTOCOL_H
#define INZONE_NI_PROTOCOL_H

#include <stdint.h>
#include <stdbool.h>

/*
 * Apple Nearby Interaction accessory protocol, as used by Apple's
 * "Implementing spatial interactions with third-party accessories"
 * sample. Messages are [1-byte id | payload] over any reliable
 * transport — here, the In-Zone BLE transport service.
 */

/* Accessory -> phone */
#define NI_MSG_ACCESSORY_CONFIG_DATA 0x01 /* payload: UWB accessory config blob */
#define NI_MSG_ACCESSORY_UWB_DID_START 0x02
#define NI_MSG_ACCESSORY_UWB_DID_STOP  0x03

/* Phone -> accessory */
#define NI_MSG_INITIALIZE 0x0A
#define NI_MSG_CONFIGURE  0x0B /* payload: NI shareableConfigurationData */
#define NI_MSG_STOP       0x0C

typedef enum {
    NI_STATE_IDLE,        /* connected, nothing exchanged */
    NI_STATE_CONFIGURED,  /* accessory config sent, awaiting CONFIGURE */
    NI_STATE_RANGING,     /* UWB session running */
} ni_state_t;

/* App-provided transport: send one protocol message to the phone.
 * Returns false if it could not be queued (caller may retry). */
typedef bool (*ni_tx_fn_t)(const uint8_t *data, uint16_t len);

void ni_protocol_init(ni_tx_fn_t tx);

/* Feed a message received from the phone. */
void ni_protocol_handle_rx(const uint8_t *data, uint16_t len);

/* Call on BLE disconnect: stops UWB and resets to IDLE. */
void ni_protocol_reset(void);

ni_state_t ni_protocol_state(void);

#endif
