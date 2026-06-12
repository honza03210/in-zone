/*
 * In-Zone anchor firmware (iOS / Apple Nearby Interaction build)
 * Target: DWM3001CDK (nRF52833 + DW3110), SoftDevice S113, bare-metal loop.
 *
 * Boot -> read identity from UICR -> advertise as "InZone-A<n>" ->
 * phone connects, runs the Apple NI accessory protocol over the
 * In-Zone transport service -> UWB ranging starts. On disconnect the
 * session is torn down and advertising resumes immediately, so the
 * phone-side round-robin scheduler can cycle through anchors quickly.
 */
#include "ble_stack.h"
#include "ni_protocol.h"
#include "uwb_port.h"
#include "anchor_id.h"
#include "leds.h"
#include "watchdog.h"
#include "cli.h"

#include "app_timer.h"
#include "nrf_pwr_mgmt.h"
#include "nrf_log.h"
#include "nrf_log_ctrl.h"
#include "nrf_log_default_backends.h"
#include "nrf_drv_clock.h"
#include "app_error.h"

static volatile bool m_connected;

static void on_conn_change(bool connected)
{
    m_connected = connected;
    /* LED state is refined in the main loop (ranging vs connected) */
    leds_set_state(connected ? LEDS_STATE_CONNECTED : LEDS_STATE_ADVERTISING);
}

static void update_leds(void)
{
    if (!m_connected) {
        return; /* advertising state already set */
    }
    leds_set_state(ni_protocol_state() == NI_STATE_RANGING
                       ? LEDS_STATE_RANGING
                       : LEDS_STATE_CONNECTED);
}

static void clock_init(void)
{
    APP_ERROR_CHECK(nrf_drv_clock_init());
    nrf_drv_clock_lfclk_request(NULL);
    while (!nrf_drv_clock_lfclk_is_running()) {
    }
}

int main(void)
{
    APP_ERROR_CHECK(NRF_LOG_INIT(NULL));
    NRF_LOG_DEFAULT_BACKENDS_INIT();

    clock_init();
    APP_ERROR_CHECK(app_timer_init());
    APP_ERROR_CHECK(nrf_pwr_mgmt_init());

    leds_init();
    watchdog_init();

    NRF_LOG_INFO("In-Zone anchor fw, id=%u label=%s",
                 anchor_id_get(), anchor_label_get());

    ble_stack_init(on_conn_change);
    ble_stack_advertising_start();
    leds_set_state(LEDS_STATE_ADVERTISING);
    cli_init();

    for (;;) {
        watchdog_feed();
        uwb_port_poll();
        cli_poll();
        update_leds();
        if (!NRF_LOG_PROCESS()) {
            nrf_pwr_mgmt_run();
        }
    }
}
