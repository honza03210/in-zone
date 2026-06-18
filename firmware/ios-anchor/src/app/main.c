/*
 * In-Zone anchor firmware (iOS / Apple Nearby Interaction build)
 * Target: DWM3001CDK (nRF52833 + DW3110), SoftDevice S113.
 *
 * Boot -> read identity from UICR -> advertise as "InZone-A<n>" ->
 * phone connects, runs the Apple NI accessory protocol over the
 * In-Zone transport service -> UWB ranging starts.
 *
 * UWB_BACKEND=qani builds on FreeRTOS (INZONE_FREERTOS): the Qorvo uwb-stack
 * needs a preemptive RTOS for SoftDevice coexistence (the MAC runs in its own
 * tasks; session start/stop blocks on qsignals). The stub backend stays a
 * bare-metal poll loop.
 */
#include "ble_stack.h"
#include "ni_protocol.h"
#include "uwb_port.h"
#include "anchor_id.h"
#include "leds.h"
#include "watchdog.h"
#include "cli.h"

#include "app_timer.h"
#include "nrf_log.h"
#include "nrf_log_ctrl.h"
#include "nrf_log_default_backends.h"
#include "nrf_drv_clock.h"
#include "app_error.h"

static volatile bool m_connected;

/* --- HardFault capture ---
 * The default weak HardFault_Handler is a bare spin loop that loses the
 * faulting context. Snapshot the exception frame + fault status registers
 * into globals so they can be read cleanly over SWD. */
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

#ifdef INZONE_FREERTOS
/* Request the HFXO (high-frequency crystal) and keep it on. The UWB MAC needs
 * a stable HFXO for radio timing. This MUST be called AFTER the SoftDevice is
 * enabled so nrf_drv_clock_hfclk_request routes through sd_clock_hfclk_request
 * (the SD then keeps the HFXO running instead of power-managing it around its
 * own radio events). Qorvo's QANI does the equivalent in its UWB bring-up. */
static void request_hfxo(void)
{
    nrf_drv_clock_hfclk_request(NULL);
    while (!nrf_drv_clock_hfclk_is_running()) {
    }
}
#endif

#ifdef INZONE_FREERTOS

#include "FreeRTOS.h"
#include "task.h"
#include "nrf_sdh_freertos.h"

/* Runs once inside the SoftDevice FreeRTOS task (after the scheduler starts):
 * begin advertising. */
static void softdevice_task_hook(void *p_context)
{
    (void)p_context;
    ble_stack_advertising_start();
    leds_set_state(LEDS_STATE_ADVERTISING);
    NRF_LOG_INFO("ble: advertising as %s", anchor_label_get());
}

/* Application housekeeping task: CLI input, LED state refinement, log flush. */
static StackType_t  m_app_stack[512];
static StaticTask_t m_app_tcb;

static void app_task(void *arg)
{
    (void)arg;
    for (;;) {
        cli_poll();
        update_leds();
        while (NRF_LOG_PROCESS()) {
            /* drain deferred logs */
        }
        vTaskDelay(pdMS_TO_TICKS(20));
    }
}

/* configUSE_IDLE_HOOK == 1: feed the watchdog from the idle task; the FreeRTOS
 * tickless-idle port puts the CPU to sleep (SoftDevice-aware) afterwards. */
void vApplicationIdleHook(void)
{
    watchdog_feed();
}

/* --- FreeRTOS diagnostic hooks (flush over RTT so they appear in capture) --- */
void vApplicationStackOverflowHook(TaskHandle_t task, char *name)
{
    (void)task;
    NRF_LOG_ERROR("FATAL: stack overflow in task '%s'", name);
    NRF_LOG_FLUSH();
    for (;;) {
    }
}

void vApplicationMallocFailedHook(void)
{
    NRF_LOG_ERROR("FATAL: pvPortMalloc failed (FreeRTOS heap exhausted)");
    NRF_LOG_FLUSH();
    for (;;) {
    }
}

void vApplicationAssert(const char *file, int line)
{
    NRF_LOG_ERROR("FATAL: FreeRTOS assert at %s:%d", file, line);
    NRF_LOG_FLUSH();
    for (;;) {
    }
}

int main(void)
{
    APP_ERROR_CHECK(NRF_LOG_INIT(NULL));
    NRF_LOG_DEFAULT_BACKENDS_INIT();

    clock_init();
    APP_ERROR_CHECK(app_timer_init());

    leds_init();
    watchdog_init();

    NRF_LOG_INFO("In-Zone anchor fw (FreeRTOS), id=%u label=%s",
                 anchor_id_get(), anchor_label_get());

    /* Bring up the UWB stack BEFORE the SoftDevice is enabled, so its
     * calibration + flash transactions run against direct NVMC (no sd_flash
     * coordination). This mirrors Qorvo's QANI, which calls fira_uwb_mcps_init
     * from CreateQaniTask() before ble_init() — "to handle calibration and
     * flash transactions before softdevice is up". (Creates the uwb_task too;
     * it runs once the scheduler starts.) */
    ni_protocol_uwb_init();

    /* Create the SoftDevice FreeRTOS task FIRST, so m_softdevice_task is valid
     * before the SD is enabled — otherwise the first SD_EVT interrupt (raised
     * during ble_stack_init) calls vTaskNotifyGiveFromISR(NULL). The task only
     * runs once the scheduler starts; its first act is nrf_sdh_evts_poll(), so
     * no early event is lost. SoftDevice events are fetched in this task
     * (NRF_SDH_DISPATCH_MODEL = POLLING) so our BLE/niq callbacks run in task
     * context where FreeRTOS APIs and pvPortMalloc are safe. The hook starts
     * advertising. */
    nrf_sdh_freertos_init(softdevice_task_hook, NULL);

    /* Enables the SoftDevice and, via ni_protocol_init -> uwb_port_init,
     * creates the UWB MAC + worker tasks (they run once the scheduler starts). */
    ble_stack_init(on_conn_change);

    /* HFXO request now that the SoftDevice owns the clock (routes via the SD). */
    request_hfxo();

    cli_init();

    xTaskCreateStatic(app_task, "app", sizeof(m_app_stack) / sizeof(StackType_t),
                      NULL, 1, m_app_stack, &m_app_tcb);

    vTaskStartScheduler();

    /* Unreachable unless the scheduler ran out of heap. */
    for (;;) {
    }
}

#else /* bare-metal stub build */

#include "nrf_pwr_mgmt.h"

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

    ni_protocol_uwb_init(); /* UWB stack up before the SoftDevice (see FreeRTOS path) */
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

#endif /* INZONE_FREERTOS */
