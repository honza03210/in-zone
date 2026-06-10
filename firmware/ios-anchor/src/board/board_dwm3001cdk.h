/*
 * DWM3001CDK board definitions (nRF52833 host, DW3110 UWB).
 * Pin map taken from the Zephyr board support for decawave_dwm3001cdk,
 * which matches the DWM3001CDK schematic rev B.
 */
#ifndef BOARD_DWM3001CDK_H
#define BOARD_DWM3001CDK_H

#include "nrf_gpio.h"

/* LEDs, all active low */
#define LED_GREEN_D9    NRF_GPIO_PIN_MAP(0, 4)   /* status: advertising/connected */
#define LED_BLUE_D10    NRF_GPIO_PIN_MAP(0, 5)   /* ranging activity */
#define LED_RED_D11     NRF_GPIO_PIN_MAP(0, 22)  /* error */
#define LED_RED_D12     NRF_GPIO_PIN_MAP(0, 14)  /* identify blink */

#define LEDS_ACTIVE_STATE 0

/* SW2 user button (SW1 is hard-wired to RESETn), active low, needs pull-up */
#define BUTTON_SW2      NRF_GPIO_PIN_MAP(0, 2)

#endif /* BOARD_DWM3001CDK_H */
