#ifndef INZONE_ANCHOR_ID_H
#define INZONE_ANCHOR_ID_H

#include <stdint.h>

/*
 * Anchor identity, provisioned into UICR customer registers with
 * scripts/provision.ps1 (survives application reflash; erased only by
 * a full chip erase, after which the anchor reports as unprovisioned).
 *
 *   UICR.CUSTOMER[0] @ 0x10001080  anchor id (0..3), 0xFFFFFFFF = unprovisioned
 *   UICR.CUSTOMER[4..7] @ 0x10001090  label, 16 bytes UTF-8, 0xFF padded
 */

#define ANCHOR_ID_UNPROVISIONED 0xFF
#define ANCHOR_LABEL_MAX_LEN    16

uint8_t anchor_id_get(void);

/* Returns NUL-terminated label; "InZone-A<id>" / "InZone-unset" fallback. */
const char *anchor_label_get(void);

/* Short device name for BLE advertising, e.g. "InZone-A2". */
const char *anchor_adv_name_get(void);

#endif
