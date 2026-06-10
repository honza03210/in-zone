#include "ble_stack.h"
#include "inzone_uuids.h"
#include "svc_ni_transport.h"
#include "svc_anchor_info.h"
#include "anchor_id.h"
#include "ni_protocol.h"

#include "nrf_sdh.h"
#include "nrf_sdh_ble.h"
#include "nrf_ble_gatt.h"
#include "ble_advertising.h"
#include "ble_conn_params.h"
#include "app_timer.h"
#include "nrf_log.h"
#include "app_error.h"
#include <string.h>

#define APP_BLE_CONN_CFG_TAG    1
#define APP_BLE_OBSERVER_PRIO   3

/* 15-30 ms: snappy accessory-config exchange and low-latency re-arm
 * for the phone-side round-robin scheduler. */
#define MIN_CONN_INTERVAL       MSEC_TO_UNITS(15, UNIT_1_25_MS)
#define MAX_CONN_INTERVAL       MSEC_TO_UNITS(30, UNIT_1_25_MS)
#define SLAVE_LATENCY           0
#define CONN_SUP_TIMEOUT        MSEC_TO_UNITS(4000, UNIT_10_MS)

#define ADV_INTERVAL            MSEC_TO_UNITS(100, UNIT_0_625_MS)
#define ADV_DURATION            0 /* advertise forever */

NRF_BLE_GATT_DEF(m_gatt);
BLE_ADVERTISING_DEF(m_advertising);

static uint8_t m_uuid_type;
static ble_stack_conn_cb_t m_conn_cb;

static bool transport_tx(const uint8_t *data, uint16_t len)
{
    return svc_ni_transport_send(data, len);
}

static void transport_rx(const uint8_t *data, uint16_t len)
{
    ni_protocol_handle_rx(data, len);
}

static void transport_ready(bool ready)
{
    if (!ready) {
        ni_protocol_reset();
    }
}

static void on_ble_evt(const ble_evt_t *p_ble_evt, void *p_context)
{
    (void)p_context;

    switch (p_ble_evt->header.evt_id) {
    case BLE_GAP_EVT_CONNECTED:
        NRF_LOG_INFO("ble: connected");
        if (m_conn_cb) {
            m_conn_cb(true);
        }
        break;

    case BLE_GAP_EVT_DISCONNECTED:
        NRF_LOG_INFO("ble: disconnected (reason 0x%x)",
                     p_ble_evt->evt.gap_evt.params.disconnected.reason);
        ni_protocol_reset();
        if (m_conn_cb) {
            m_conn_cb(false);
        }
        /* ble_advertising restarts advertising automatically */
        break;

    case BLE_GAP_EVT_PHY_UPDATE_REQUEST: {
        ble_gap_phys_t phys = {
            .rx_phys = BLE_GAP_PHY_AUTO,
            .tx_phys = BLE_GAP_PHY_AUTO,
        };
        APP_ERROR_CHECK(sd_ble_gap_phy_update(
            p_ble_evt->evt.gap_evt.conn_handle, &phys));
        break;
    }

    default:
        break;
    }

    svc_ni_transport_on_ble_evt(p_ble_evt, NULL);
    svc_anchor_info_on_ble_evt(p_ble_evt, NULL);
}

NRF_SDH_BLE_OBSERVER(m_ble_observer, APP_BLE_OBSERVER_PRIO, on_ble_evt, NULL);

static void gap_params_init(void)
{
    ble_gap_conn_sec_mode_t sec_mode;
    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&sec_mode);

    const char *name = anchor_adv_name_get();
    APP_ERROR_CHECK(sd_ble_gap_device_name_set(
        &sec_mode, (const uint8_t *)name, strlen(name)));

    ble_gap_conn_params_t conn_params = {
        .min_conn_interval = MIN_CONN_INTERVAL,
        .max_conn_interval = MAX_CONN_INTERVAL,
        .slave_latency     = SLAVE_LATENCY,
        .conn_sup_timeout  = CONN_SUP_TIMEOUT,
    };
    APP_ERROR_CHECK(sd_ble_gap_ppcp_set(&conn_params));
}

static void advertising_init(void)
{
    ble_advertising_init_t init = {0};

    /* 128-bit service UUID fills the adv packet; name goes in scan rsp */
    static ble_uuid_t adv_uuids[1];
    adv_uuids[0].uuid = INZONE_UUID_SVC_TRANSPORT;
    adv_uuids[0].type = m_uuid_type;

    init.advdata.flags = BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE;
    init.advdata.uuids_complete.uuid_cnt = 1;
    init.advdata.uuids_complete.p_uuids  = adv_uuids;

    init.srdata.name_type = BLE_ADVDATA_FULL_NAME;

    init.config.ble_adv_fast_enabled  = true;
    init.config.ble_adv_fast_interval = ADV_INTERVAL;
    init.config.ble_adv_fast_timeout  = ADV_DURATION;
    init.config.ble_adv_on_disconnect_disabled = false;

    APP_ERROR_CHECK(ble_advertising_init(&m_advertising, &init));
    ble_advertising_conn_cfg_tag_set(&m_advertising, APP_BLE_CONN_CFG_TAG);
}

static void conn_params_init(void)
{
    ble_conn_params_init_t init = {0};

    init.first_conn_params_update_delay = APP_TIMER_TICKS(5000);
    init.next_conn_params_update_delay  = APP_TIMER_TICKS(30000);
    init.max_conn_params_update_count   = 3;
    init.disconnect_on_fail             = false;

    APP_ERROR_CHECK(ble_conn_params_init(&init));
}

void ble_stack_init(ble_stack_conn_cb_t conn_cb)
{
    m_conn_cb = conn_cb;

    APP_ERROR_CHECK(nrf_sdh_enable_request());

    uint32_t ram_start = 0;
    APP_ERROR_CHECK(nrf_sdh_ble_default_cfg_set(APP_BLE_CONN_CFG_TAG, &ram_start));
    APP_ERROR_CHECK(nrf_sdh_ble_enable(&ram_start));
    NRF_LOG_INFO("ble: SoftDevice RAM start 0x%08x", ram_start);

    ble_uuid128_t base = { INZONE_UUID_BASE };
    APP_ERROR_CHECK(sd_ble_uuid_vs_add(&base, &m_uuid_type));

    gap_params_init();
    APP_ERROR_CHECK(nrf_ble_gatt_init(&m_gatt, NULL));
    APP_ERROR_CHECK(nrf_ble_gatt_att_mtu_periph_set(
        &m_gatt, NRF_SDH_BLE_GATT_MAX_MTU_SIZE));

    svc_ni_transport_init(m_uuid_type, transport_rx, transport_ready);
    svc_anchor_info_init(m_uuid_type);
    ni_protocol_init(transport_tx);

    advertising_init();
    conn_params_init();
}

void ble_stack_advertising_start(void)
{
    APP_ERROR_CHECK(ble_advertising_start(&m_advertising, BLE_ADV_MODE_FAST));
    NRF_LOG_INFO("ble: advertising as %s", anchor_adv_name_get());
}
