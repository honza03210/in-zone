#include "ni_protocol.h"
#include "uwb_port.h"
#include "nrf_log.h"
#include <string.h>

/* Accessory config blobs observed from niq are < 64 B; leave headroom. */
#define ACCESSORY_CONFIG_MAX 128

static ni_tx_fn_t m_tx;
static ni_state_t m_state = NI_STATE_IDLE;

static void send_msg(uint8_t id, const uint8_t *payload, uint16_t len)
{
    static uint8_t buf[1 + ACCESSORY_CONFIG_MAX];

    if (len > sizeof(buf) - 1) {
        NRF_LOG_ERROR("ni: tx payload too large (%u)", len);
        return;
    }
    buf[0] = id;
    if (len > 0) {
        memcpy(&buf[1], payload, len);
    }
    if (!m_tx(buf, (uint16_t)(1 + len))) {
        NRF_LOG_WARNING("ni: tx of msg 0x%02x failed", id);
    }
}

static void uwb_evt_handler(uwb_port_evt_t evt)
{
    switch (evt) {
    case UWB_PORT_EVT_STARTED:
        m_state = NI_STATE_RANGING;
        send_msg(NI_MSG_ACCESSORY_UWB_DID_START, NULL, 0);
        NRF_LOG_INFO("ni: uwb started");
        break;

    case UWB_PORT_EVT_STOPPED:
        m_state = NI_STATE_IDLE;
        send_msg(NI_MSG_ACCESSORY_UWB_DID_STOP, NULL, 0);
        NRF_LOG_INFO("ni: uwb stopped");
        break;

    case UWB_PORT_EVT_RANGE:
        break;

    case UWB_PORT_EVT_ERROR:
        m_state = NI_STATE_IDLE;
        NRF_LOG_ERROR("ni: uwb error");
        break;
    }
}

static void handle_initialize(void)
{
    uint8_t cfg[ACCESSORY_CONFIG_MAX];
    uint16_t len = sizeof(cfg);

    if (uwb_port_get_accessory_config(cfg, &len) != 0) {
        NRF_LOG_ERROR("ni: failed to get accessory config");
        return;
    }
    send_msg(NI_MSG_ACCESSORY_CONFIG_DATA, cfg, len);
    m_state = NI_STATE_CONFIGURED;
    NRF_LOG_INFO("ni: sent accessory config (%u bytes)", len);
}

void ni_protocol_uwb_init(void)
{
    uwb_port_init(uwb_evt_handler);
}

void ni_protocol_init(ni_tx_fn_t tx)
{
    m_tx = tx;
    m_state = NI_STATE_IDLE;
}

void ni_protocol_handle_rx(const uint8_t *data, uint16_t len)
{
    if (len < 1) {
        return;
    }

    switch (data[0]) {
    case NI_MSG_INITIALIZE:
        handle_initialize();
        break;

    case NI_MSG_CONFIGURE:
        if (m_state != NI_STATE_CONFIGURED) {
            NRF_LOG_WARNING("ni: CONFIGURE in state %d, ignoring", m_state);
            return;
        }
        if (uwb_port_start(&data[1], (uint16_t)(len - 1)) != 0) {
            NRF_LOG_ERROR("ni: uwb start failed");
            m_state = NI_STATE_IDLE;
        }
        break;

    case NI_MSG_STOP:
        uwb_port_stop();
        break;

    default:
        NRF_LOG_WARNING("ni: unknown msg 0x%02x", data[0]);
        break;
    }
}

void ni_protocol_reset(void)
{
    if (m_state == NI_STATE_RANGING) {
        uwb_port_stop();
    }
    m_state = NI_STATE_IDLE;
}

ni_state_t ni_protocol_state(void)
{
    return m_state;
}
