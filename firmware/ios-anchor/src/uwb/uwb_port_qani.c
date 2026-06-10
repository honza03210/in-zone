/*
 * Qorvo QANI UWB backend (UWB_BACKEND=qani).
 *
 * Bridges uwb_port.h to Qorvo's niq library (Apple Nearby Interaction)
 * and uwbstack, both shipped as binary libs + headers in the
 * registration-gated "Qorvo Nearby Interaction" (QANI) package.
 * Unpack the package into firmware/vendor/qani/ — see vendor/README.md.
 *
 * !! INTEGRATION FILE !!
 * The niq API below uses the function names confirmed from QANI 3.x
 * (see Apps/.../ble_niq.c in the package), but exact signatures vary
 * between SDK releases. Each call site is tagged VERIFY(file) — diff it
 * against the same call in the package's reference app before building.
 * All Qorvo-specific code is confined to this one file on purpose.
 */
#include "uwb_port.h"
#include "nrf_log.h"

#include "niq.h" /* from vendor/qani — Apple NI accessory library */

static uwb_port_evt_cb_t m_cb;

/* VERIFY(ble_niq.c): niq ranging-started/stopped callbacks. QANI registers
 * these via niq_init(); adapt names/params to the package in use. */
static void on_uwb_started(void)
{
    if (m_cb) {
        m_cb(UWB_PORT_EVT_STARTED);
    }
}

static void on_uwb_stopped(void)
{
    if (m_cb) {
        m_cb(UWB_PORT_EVT_STOPPED);
    }
}

int uwb_port_init(uwb_port_evt_cb_t cb)
{
    m_cb = cb;

    /* VERIFY(main.c/ble_niq.c): QANI inits the UWB MAC + niq once at boot;
     * typical sequence is uwb_mac init followed by:
     *   niq_init(on_uwb_started, on_uwb_stopped, ...);
     */
    niq_init(on_uwb_started, on_uwb_stopped);

    NRF_LOG_INFO("uwb: QANI backend initialised");
    return 0;
}

int uwb_port_get_accessory_config(uint8_t *buf, uint16_t *len)
{
    /* VERIFY(ble_niq.c): populates the Apple NI accessory configuration
     * data blob the phone needs for NINearbyAccessoryConfiguration. */
    return niq_populate_accessory_uwb_config_data(buf, len);
}

int uwb_port_start(const uint8_t *shareable_cfg, uint16_t len)
{
    /* VERIFY(ble_niq.c): consumes the phone's shareableConfigurationData
     * and starts the UWB session. Completion arrives via on_uwb_started. */
    return niq_configure_and_start_uwb(shareable_cfg, len);
}

int uwb_port_stop(void)
{
    /* VERIFY(ble_niq.c) */
    niq_stop_uwb();
    return 0;
}
