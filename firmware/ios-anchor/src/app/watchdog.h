#ifndef INZONE_WATCHDOG_H
#define INZONE_WATCHDOG_H

/* 8 s hardware watchdog; feed from the main idle loop. Recovers anchors
 * from firmware hangs without a trip across the room. */
void watchdog_init(void);
void watchdog_feed(void);

#endif
