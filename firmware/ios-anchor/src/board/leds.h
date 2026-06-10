#ifndef INZONE_LEDS_H
#define INZONE_LEDS_H

#include <stdint.h>

/* High-level anchor states mapped to LED patterns (see leds.c). */
typedef enum {
    LEDS_STATE_BOOT,         /* all on briefly */
    LEDS_STATE_ADVERTISING,  /* green slow blink */
    LEDS_STATE_CONNECTED,    /* green solid */
    LEDS_STATE_RANGING,      /* green solid + blue blink */
    LEDS_STATE_ERROR,        /* red D11 solid */
} leds_state_t;

void leds_init(void);
void leds_set_state(leds_state_t state);

/* Blink red D12 for `seconds` so the user can find this anchor ("identify"). */
void leds_identify(uint8_t seconds);

#endif
