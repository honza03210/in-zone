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

/* --- HardFault capture ---
 * The default weak HardFault_Handler is a bare spin loop that loses the
 * faulting context. Snapshot the exception frame + fault status registers
 * into globals so they can be read cleanly over SWD during QANI bring-up. */
volatile uint32_t g_fault[8];   /* r0,r1,r2,r3,r12,lr,pc,xpsr */
volatile uint32_t g_cfsr, g_hfsr, g_bfar, g_mmfar;
volatile uint32_t g_fault_lr;   /* EXC_RETURN */

void hard_fault_capture(uint32_t *frame, uint32_t exc_return)
{
    for (int i = 0; i < 8; i++) {
        g_fault[i] = frame[i];
    }
    g_fault_lr = exc_return;
    g_cfsr  = *(volatile uint32_t *)0xE000ED28;
    g_hfsr  = *(volatile uint32_t *)0xE000ED2C;
    g_mmfar = *(volatile uint32_t *)0xE000ED34;
    g_bfar  = *(volatile uint32_t *)0xE000ED38;
    for (;;) {
        __asm volatile("nop");
    }
}

__attribute__((naked)) void HardFault_Handler(void)
{
    __asm volatile(
        "tst lr, #4            \n"
        "ite eq                \n"
        "mrseq r0, msp         \n"
        "mrsne r0, psp         \n"
        "mov  r1, lr           \n"
        "b    hard_fault_capture\n"
    );
}

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
