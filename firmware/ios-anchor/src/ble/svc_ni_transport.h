#ifndef INZONE_SVC_NI_TRANSPORT_H
#define INZONE_SVC_NI_TRANSPORT_H

#include <stdint.h>
#include <stdbool.h>
#include "ble.h"

/*
 * In-Zone NI transport service: a NUS-style pipe carrying Apple NI
 * accessory protocol messages. RX = phone writes, TX = notifications.
 */

typedef void (*ni_transport_rx_cb_t)(const uint8_t *data, uint16_t len);

/* Phone enabled/disabled TX notifications — session can start when true. */
typedef void (*ni_transport_ready_cb_t)(bool ready);

void svc_ni_transport_init(uint8_t uuid_type,
                           ni_transport_rx_cb_t rx_cb,
                           ni_transport_ready_cb_t ready_cb);

/* Send one message to the phone. False if not connected/subscribed or
 * the SoftDevice queue is full. */
bool svc_ni_transport_send(const uint8_t *data, uint16_t len);

void svc_ni_transport_on_ble_evt(const ble_evt_t *p_ble_evt, void *p_context);

#endif
