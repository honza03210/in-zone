#include "svc_ni_transport.h"
#include "inzone_uuids.h"
#include "ble_srv_common.h"
#include "nrf_log.h"
#include "app_error.h"

static uint16_t m_service_handle;
static ble_gatts_char_handles_t m_rx_handles;
static ble_gatts_char_handles_t m_tx_handles;
static uint16_t m_conn_handle = BLE_CONN_HANDLE_INVALID;
static bool m_notifications_enabled;

static ni_transport_rx_cb_t m_rx_cb;
static ni_transport_ready_cb_t m_ready_cb;

static void add_rx_char(uint8_t uuid_type)
{
    ble_add_char_params_t p = {0};

    p.uuid              = INZONE_UUID_CHR_RX;
    p.uuid_type         = uuid_type;
    p.max_len           = BLE_GATT_ATT_MTU_DEFAULT + 100; /* variable */
    p.init_len          = 1;
    p.is_var_len        = true;
    p.char_props.write  = 1;
    p.char_props.write_wo_resp = 1;
    p.write_access      = SEC_OPEN;

    APP_ERROR_CHECK(characteristic_add(m_service_handle, &p, &m_rx_handles));
}

static void add_tx_char(uint8_t uuid_type)
{
    ble_add_char_params_t p = {0};

    p.uuid              = INZONE_UUID_CHR_TX;
    p.uuid_type         = uuid_type;
    p.max_len           = BLE_GATT_ATT_MTU_DEFAULT + 100;
    p.init_len          = 1;
    p.is_var_len        = true;
    p.char_props.notify = 1;
    p.cccd_write_access = SEC_OPEN;

    APP_ERROR_CHECK(characteristic_add(m_service_handle, &p, &m_tx_handles));
}

void svc_ni_transport_init(uint8_t uuid_type,
                           ni_transport_rx_cb_t rx_cb,
                           ni_transport_ready_cb_t ready_cb)
{
    m_rx_cb = rx_cb;
    m_ready_cb = ready_cb;

    ble_uuid_t svc_uuid = { .uuid = INZONE_UUID_SVC_TRANSPORT, .type = uuid_type };
    APP_ERROR_CHECK(sd_ble_gatts_service_add(BLE_GATTS_SRVC_TYPE_PRIMARY,
                                             &svc_uuid, &m_service_handle));
    add_rx_char(uuid_type);
    add_tx_char(uuid_type);
}

bool svc_ni_transport_send(const uint8_t *data, uint16_t len)
{
    if (m_conn_handle == BLE_CONN_HANDLE_INVALID || !m_notifications_enabled) {
        return false;
    }

    uint16_t hvx_len = len;
    ble_gatts_hvx_params_t hvx = {
        .handle = m_tx_handles.value_handle,
        .type   = BLE_GATT_HVX_NOTIFICATION,
        .p_len  = &hvx_len,
        .p_data = data,
    };

    uint32_t err = sd_ble_gatts_hvx(m_conn_handle, &hvx);
    if (err != NRF_SUCCESS) {
        NRF_LOG_WARNING("transport: hvx err 0x%x", err);
        return false;
    }
    return hvx_len == len;
}

void svc_ni_transport_on_ble_evt(const ble_evt_t *p_ble_evt, void *p_context)
{
    (void)p_context;

    switch (p_ble_evt->header.evt_id) {
    case BLE_GAP_EVT_CONNECTED:
        m_conn_handle = p_ble_evt->evt.gap_evt.conn_handle;
        m_notifications_enabled = false;
        break;

    case BLE_GAP_EVT_DISCONNECTED:
        m_conn_handle = BLE_CONN_HANDLE_INVALID;
        m_notifications_enabled = false;
        if (m_ready_cb) {
            m_ready_cb(false);
        }
        break;

    case BLE_GATTS_EVT_WRITE: {
        const ble_gatts_evt_write_t *w = &p_ble_evt->evt.gatts_evt.params.write;

        if (w->handle == m_rx_handles.value_handle && m_rx_cb) {
            m_rx_cb(w->data, w->len);
        } else if (w->handle == m_tx_handles.cccd_handle && w->len == 2) {
            m_notifications_enabled = ble_srv_is_notification_enabled(w->data);
            if (m_ready_cb) {
                m_ready_cb(m_notifications_enabled);
            }
        }
        break;
    }

    default:
        break;
    }
}
