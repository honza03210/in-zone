#ifndef INZONE_SVC_ANCHOR_INFO_H
#define INZONE_SVC_ANCHOR_INFO_H

#include "ble.h"

/*
 * Anchor info service: read-only identity (id, label, fw version, mode)
 * plus an "identify" characteristic that blinks the red LED so the user
 * can match a BLE device to a physical anchor during setup.
 */

void svc_anchor_info_init(uint8_t uuid_type);
void svc_anchor_info_on_ble_evt(const ble_evt_t *p_ble_evt, void *p_context);

#endif
