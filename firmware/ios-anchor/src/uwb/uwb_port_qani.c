/*
 * Qorvo QANI UWB backend (UWB_BACKEND=qani).
 *
 * Bridges uwb_port.h to Qorvo's niq library (Apple Nearby Interaction)
 * and uwbstack, shipped as binary libs + headers in the DW3_QM33_SDK.
 *
 * The reference integration files are:
 *   SDK/Firmware/Src/Comm/Src/BLE/niq/ble_niq.c     — protocol handling
 *   SDK/Firmware/Projects/FreeRTOS/QANI/Common/src/fira/fira_niq.c — UWB session
 *   SDK/Firmware/Projects/FreeRTOS/QANI/Common/src/main.c — niq_init call
 *   SDK/Firmware/Src/HAL/Src/nrfx/HAL_crypto.c       — crypto callbacks
 *
 * This file is the ONLY Qorvo-API-aware file in our tree.
 */
#include "uwb_port.h"
#include "nrf_log.h"

#include "niq.h"

#include "nrf_soc.h"

#include <string.h>

static void crypto_init_cb(void)
{
}

static void crypto_deinit_cb(void)
{
}

static void crypto_get_random_vector_cb(uint8_t *const p_target, size_t size)
{
    uint8_t *p = p_target;
    size_t remaining = size;

    while (remaining > 0) {
        uint8_t available = 0;
        sd_rand_application_bytes_available_get(&available);
        if (available > 0) {
            uint8_t chunk = (available < remaining) ? available : (uint8_t)remaining;
            if (sd_rand_application_vector_get(p, chunk) == NRF_SUCCESS) {
                p += chunk;
                remaining -= chunk;
            }
        }
    }
}

/* ACCESSORY_RANGING_ROLE: 0 = Controlee+Responder (standard for NI accessories) */
#define ACCESSORY_RANGING_ROLE 0

/* We use conn_id 0 for the single NI connection our firmware supports. */
#define CONN_ID 0

static uwb_port_evt_cb_t m_cb;

/* Default FiRa config populated by niq_configure_and_start_uwb; the niq
 * library fills in session parameters from the phone's shareable config.
 * Starting values here match Qorvo's ble_niq.c reference defaults. */
static fira_device_configure_t m_fira_config = {
    .role                           = 0, /* set by niq */
    .enc_payload                    = 1,
    .Session_ID                     = 1111,
    .Ranging_Round_Usage            = 3,  /* DSTWR deferred */
    .Multi_Node_Mode                = 0,  /* unicast */
    .Rframe_Config                  = 3,  /* SP3 */
    .ToF_Report                     = 1,
    .AoA_Azimuth_Report             = 0,
    .AoA_Elevation_Report           = 0,
    .AoA_FOM_Report                 = 0,
    .nonDeferred_Mode               = 0,
    .STS_Config                     = 0,
    .Round_Hopping                  = 0,
    .Block_Striding                 = 0,
    .Block_Duration_ms              = 100,
    .Round_Duration_RSTU            = 18400,
    .Slot_Duration_RSTU             = 2400,
    .Channel_Number                 = 9,
    .Preamble_Code                  = 11,
    .PRF_Mode                       = 0,
    .SP0_PHY_Set                    = 2, /* BPRF_SET_2 */
    .SP1_PHY_Set                    = 3,
    .SP3_PHY_Set                    = 4,
    .MAX_RR_Retry                   = 1,
    .Constraint_Length_Conv_Code_HPRF = 0,
    .UWB_Init_Time_ms               = 5,
    .Block_Timing_Stability         = 0,
    .Key_Rotation                   = 0,
    .Key_Rotation_Rate              = 0,
    .MAC_FCS_TYPE                   = 0,
    .MAC_ADDRESS_MODE               = 0,
    .SRC_ADDR                       = {0, 0},
    .Number_of_Controlee            = 1,
    .DST_ADDR                       = {1, 0},
    .Vendor_ID                      = {0, 0},
    .Static_STS_IV                  = {0},
};

/*
 * niq_init callbacks — niq calls start_uwb/stop_uwb when the phone's
 * shareable config has been parsed and a session needs to run/stop.
 *
 * In the Qorvo reference app these launch a FreeRTOS task that does the
 * full uwbmac init → fira_helper sequence. Our bare-metal firmware
 * doesn't use FreeRTOS or uwbmac; instead we just signal the event.
 *
 * !! IMPORTANT !! For actual UWB ranging to work, the uwbmac/fira_helper
 * session-start sequence from fira_niq.c must be ported here. The code
 * below is the minimal skeleton that makes the BLE protocol work end-to-
 * end and reports events to the app; ranging output requires porting
 * fira_niq_app_process_init() and its uwbmac calls. See fira_niq.c in
 * the SDK for the full sequence.
 */
static void on_niq_start_uwb(fira_device_configure_t *config, void *user_ctx)
{
    (void)user_ctx;
    NRF_LOG_INFO("uwb: niq requests start (session %u, ch %u)",
                 config->Session_ID, config->Channel_Number);

    /* TODO: port fira_niq.c fira_start_niq() sequence:
     *   fira_uwb_mcps_init → fira_helper_open → fira_helper_set_scheduler →
     *   fira_helper_init_session → fira_set_session_parameters →
     *   uwbmac_start → fira_helper_start_session
     * Until then, we report started so the BLE protocol completes. */

    if (m_cb) {
        m_cb(UWB_PORT_EVT_STARTED);
    }
}

static void on_niq_stop_uwb(uint32_t session_id, void *user_ctx)
{
    (void)user_ctx;
    NRF_LOG_INFO("uwb: niq requests stop (session %u)", session_id);

    /* TODO: port fira_niq.c fira_stop_niq() sequence:
     *   uwbmac_stop → fira_helper_stop_session →
     *   fira_helper_deinit_session → fira_helper_close */

    if (m_cb) {
        m_cb(UWB_PORT_EVT_STOPPED);
    }
}

int uwb_port_init(uwb_port_evt_cb_t cb)
{
    m_cb = cb;

    int ret = niq_init(
        on_niq_start_uwb,
        on_niq_stop_uwb,
        crypto_init_cb,
        crypto_deinit_cb,
        crypto_get_random_vector_cb
    );

    if (ret != 0) {
        NRF_LOG_ERROR("uwb: niq_init failed (%d)", ret);
        return ret;
    }

    NRF_LOG_INFO("uwb: QANI backend initialised (niq v2.1)");
    return 0;
}

int uwb_port_get_accessory_config(uint8_t *buf, uint16_t *len)
{
    /* niq_populate_accessory_uwb_config_data fills the UWB portion of
     * AccessoryConfigurationData. We assemble the full structure here,
     * matching ble_niq.c send_accessory_config_data(). */
    struct AccessoryConfigurationData cfg;
    memset(&cfg, 0, sizeof(cfg));

    cfg.majorVersion = NI_ACCESSORY_PROTOCOL_SPEC_MAJOR_VERSION;
    cfg.minorVersion = NI_ACCESSORY_PROTOCOL_SPEC_MINOR_VERSION;
    cfg.preferredUpdateRate = PreferredUpdateRate_UserInteractive;

    int ret = niq_populate_accessory_uwb_config_data(
        CONN_ID,
        ACCESSORY_RANGING_ROLE,
        cfg.uwbConfigData,
        &cfg.uwbConfigDataLength
    );
    if (ret != 0) {
        NRF_LOG_ERROR("uwb: populate_config failed (%d)", ret);
        return ret;
    }

    uint16_t total = ACCESSORY_CONFIGURATION_DATA_FIX_LEN + cfg.uwbConfigDataLength;
    if (*len < total) {
        return -1;
    }

    memcpy(buf, &cfg, total);
    *len = total;
    return 0;
}

int uwb_port_start(const uint8_t *shareable_cfg, uint16_t len)
{
    int ret = niq_configure_and_start_uwb(
        CONN_ID,
        (uint8_t *)shareable_cfg,
        (uint8_t)len,
        &m_fira_config,
        NULL
    );

    if (ret != 0) {
        NRF_LOG_ERROR("uwb: configure_and_start failed (%d)", ret);
        if (m_cb) {
            m_cb(UWB_PORT_EVT_ERROR);
        }
    }
    /* Success signalled via on_niq_start_uwb callback */
    return ret;
}

int uwb_port_stop(void)
{
    int ret = niq_stop_uwb(CONN_ID, NULL);
    /* Stop event signalled via on_niq_stop_uwb callback */
    return ret;
}
