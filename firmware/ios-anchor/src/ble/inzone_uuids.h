#ifndef INZONE_UUIDS_H
#define INZONE_UUIDS_H

/*
 * In-Zone vendor-specific UUIDs. One 128-bit base, 16-bit aliases in
 * bytes 12-13. Base (big-endian display form):
 *   49A7xxxx-9A91-4B5C-8E3F-2D1C7A6B5E40
 * Keep in sync with the iOS app (BLEManager.swift) and Android app.
 */

/* SoftDevice wants the base little-endian */
#define INZONE_UUID_BASE                                            \
    { 0x40, 0x5E, 0x6B, 0x7A, 0x1C, 0x2D, 0x3F, 0x8E,              \
      0x5C, 0x4B, 0x91, 0x9A, 0x00, 0x00, 0xA7, 0x49 }

/* NI transport service: accessory protocol messages */
#define INZONE_UUID_SVC_TRANSPORT   0x0001
#define INZONE_UUID_CHR_RX          0x0002 /* phone -> anchor, Write / WriteNR */
#define INZONE_UUID_CHR_TX          0x0003 /* anchor -> phone, Notify */

/* Anchor info service: identity + utilities */
#define INZONE_UUID_SVC_INFO        0x0010
#define INZONE_UUID_CHR_ANCHOR_ID   0x0011 /* read, uint8, 0xFF = unprovisioned */
#define INZONE_UUID_CHR_LABEL       0x0012 /* read, UTF-8, <=16 bytes */
#define INZONE_UUID_CHR_FW_VERSION  0x0013 /* read, UTF-8 semver */
#define INZONE_UUID_CHR_MODE        0x0014 /* read, uint8: 0 = iOS/NI */
#define INZONE_UUID_CHR_IDENTIFY    0x0015 /* write, uint8 seconds: blink LED */

#define INZONE_FW_VERSION_STRING    "0.1.0"
#define INZONE_MODE_IOS_NI          0x00

#endif
