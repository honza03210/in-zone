#include "watchdog.h"
#include "nrfx_wdt.h"
#include "app_error.h"

static nrfx_wdt_channel_id m_channel;

static void wdt_event_handler(void)
{
    /* ~60 us until reset; nothing useful to do */
}

void watchdog_init(void)
{
    nrfx_wdt_config_t config = NRFX_WDT_DEAFULT_CONFIG; /* sic: nrfx typo */
    config.reload_value = 8000; /* ms */

    APP_ERROR_CHECK(nrfx_wdt_init(&config, wdt_event_handler));
    APP_ERROR_CHECK(nrfx_wdt_channel_alloc(&m_channel));
    nrfx_wdt_enable();
}

void watchdog_feed(void)
{
    nrfx_wdt_channel_feed(m_channel);
}
