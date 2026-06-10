/*
 * Stub UWB backend (UWB_BACKEND=stub).
 *
 * Lets the whole BLE + NI-protocol stack build, flash, and exercise the
 * message exchange without the Qorvo SDK. The fake accessory config blob
 * is NOT a valid NI configuration: on the phone,
 * NINearbyAccessoryConfiguration(data:) will throw. That is expected —
 * stub mode is for testing BLE plumbing, not ranging.
 */
#include "uwb_port.h"
#include "nrf_log.h"
#include <string.h>

static uwb_port_evt_cb_t m_cb;

int uwb_port_init(uwb_port_evt_cb_t cb)
{
    m_cb = cb;
    NRF_LOG_WARNING("uwb: STUB backend - no ranging possible");
    return 0;
}

int uwb_port_get_accessory_config(uint8_t *buf, uint16_t *len)
{
    static const uint8_t fake_cfg[] = {
        'I', 'N', 'Z', 'O', 'N', 'E', '-', 'S', 'T', 'U', 'B',
        0x00, 0x01, 0x02, 0x03,
    };

    if (*len < sizeof(fake_cfg)) {
        return -1;
    }
    memcpy(buf, fake_cfg, sizeof(fake_cfg));
    *len = sizeof(fake_cfg);
    return 0;
}

int uwb_port_start(const uint8_t *shareable_cfg, uint16_t len)
{
    (void)shareable_cfg;
    NRF_LOG_INFO("uwb: stub start (%u bytes shareable cfg)", len);
    if (m_cb) {
        m_cb(UWB_PORT_EVT_STARTED);
    }
    return 0;
}

int uwb_port_stop(void)
{
    NRF_LOG_INFO("uwb: stub stop");
    if (m_cb) {
        m_cb(UWB_PORT_EVT_STOPPED);
    }
    return 0;
}
