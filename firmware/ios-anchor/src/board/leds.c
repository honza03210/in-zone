#include "leds.h"
#include "board_dwm3001cdk.h"
#include "app_timer.h"
#include "nrf_gpio.h"
#include <stdbool.h>

APP_TIMER_DEF(m_blink_timer);
APP_TIMER_DEF(m_identify_timer);

static leds_state_t m_state = LEDS_STATE_BOOT;
static bool m_blink_phase;
static uint16_t m_identify_ticks_left;

static void led_write(uint32_t pin, bool on)
{
    if (on) {
        nrf_gpio_pin_clear(pin); /* active low */
    } else {
        nrf_gpio_pin_set(pin);
    }
}

static void apply_state(void)
{
    bool green = false, blue = false, red = false;

    switch (m_state) {
    case LEDS_STATE_BOOT:        green = blue = red = true;       break;
    case LEDS_STATE_ADVERTISING: green = m_blink_phase;           break;
    case LEDS_STATE_CONNECTED:   green = true;                    break;
    case LEDS_STATE_RANGING:     green = true; blue = m_blink_phase; break;
    case LEDS_STATE_ERROR:       red = true;                      break;
    }

    led_write(LED_GREEN_D9, green);
    led_write(LED_BLUE_D10, blue);
    led_write(LED_RED_D11, red);
}

static void blink_timer_handler(void *p_context)
{
    (void)p_context;
    m_blink_phase = !m_blink_phase;
    apply_state();
}

static void identify_timer_handler(void *p_context)
{
    (void)p_context;
    if (m_identify_ticks_left > 0) {
        m_identify_ticks_left--;
        led_write(LED_RED_D12, m_identify_ticks_left & 1);
    } else {
        led_write(LED_RED_D12, false);
        app_timer_stop(m_identify_timer);
    }
}

void leds_init(void)
{
    nrf_gpio_cfg_output(LED_GREEN_D9);
    nrf_gpio_cfg_output(LED_BLUE_D10);
    nrf_gpio_cfg_output(LED_RED_D11);
    nrf_gpio_cfg_output(LED_RED_D12);
    led_write(LED_RED_D12, false);

    APP_ERROR_CHECK(app_timer_create(&m_blink_timer, APP_TIMER_MODE_REPEATED,
                                     blink_timer_handler));
    APP_ERROR_CHECK(app_timer_create(&m_identify_timer, APP_TIMER_MODE_REPEATED,
                                     identify_timer_handler));
    APP_ERROR_CHECK(app_timer_start(m_blink_timer, APP_TIMER_TICKS(500), NULL));

    leds_set_state(LEDS_STATE_BOOT);
}

void leds_set_state(leds_state_t state)
{
    m_state = state;
    apply_state();
}

void leds_identify(uint8_t seconds)
{
    /* 4 Hz toggle; counter is in timer ticks (250 ms) */
    m_identify_ticks_left = (uint16_t)seconds * 4;
    app_timer_stop(m_identify_timer);
    APP_ERROR_CHECK(app_timer_start(m_identify_timer, APP_TIMER_TICKS(250), NULL));
}
