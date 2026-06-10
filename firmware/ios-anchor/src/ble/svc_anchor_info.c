#include "svc_anchor_info.h"
#include "inzone_uuids.h"
#include "anchor_id.h"
#include "leds.h"
#include "ble_srv_common.h"
#include "app_error.h"
#include <string.h>

static uint16_t m_service_handle;
static ble_gatts_char_handles_t m_identify_handles;

static void add_ro_char(uint8_t uuid_type, uint16_t uuid,
                        const uint8_t *value, uint16_t len)
{
    ble_add_char_params_t p = {0};
    ble_gatts_char_handles_t handles;

    p.uuid             = uuid;
    p.uuid_type        = uuid_type;
    p.max_len          = len;
    p.init_len         = len;
    p.p_init_value     = (uint8_t *)value;
    p.char_props.read  = 1;
    p.read_access      = SEC_OPEN;

    APP_ERROR_CHECK(characteristic_add(m_service_handle, &p, &handles));
}

void svc_anchor_info_init(uint8_t uuid_type)
{
    ble_uuid_t svc_uuid = { .uuid = INZONE_UUID_SVC_INFO, .type = uuid_type };
    APP_ERROR_CHECK(sd_ble_gatts_service_add(BLE_GATTS_SRVC_TYPE_PRIMARY,
                                             &svc_uuid, &m_service_handle));

    uint8_t id = anchor_id_get();
    add_ro_char(uuid_type, INZONE_UUID_CHR_ANCHOR_ID, &id, 1);

    const char *label = anchor_label_get();
    add_ro_char(uuid_type, INZONE_UUID_CHR_LABEL,
                (const uint8_t *)label, (uint16_t)strlen(label));

    add_ro_char(uuid_type, INZONE_UUID_CHR_FW_VERSION,
                (const uint8_t *)INZONE_FW_VERSION_STRING,
                sizeof(INZONE_FW_VERSION_STRING) - 1);

    uint8_t mode = INZONE_MODE_IOS_NI;
    add_ro_char(uuid_type, INZONE_UUID_CHR_MODE, &mode, 1);

    ble_add_char_params_t p = {0};
    p.uuid              = INZONE_UUID_CHR_IDENTIFY;
    p.uuid_type         = uuid_type;
    p.max_len           = 1;
    p.init_len          = 1;
    p.char_props.write  = 1;
    p.write_access      = SEC_OPEN;
    APP_ERROR_CHECK(characteristic_add(m_service_handle, &p, &m_identify_handles));
}

void svc_anchor_info_on_ble_evt(const ble_evt_t *p_ble_evt, void *p_context)
{
    (void)p_context;

    if (p_ble_evt->header.evt_id != BLE_GATTS_EVT_WRITE) {
        return;
    }

    const ble_gatts_evt_write_t *w = &p_ble_evt->evt.gatts_evt.params.write;
    if (w->handle == m_identify_handles.value_handle && w->len == 1) {
        uint8_t seconds = (w->data[0] == 0) ? 5 : w->data[0];
        leds_identify(seconds);
    }
}
