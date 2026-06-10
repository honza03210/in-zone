/*
 * Qorvo QANI UWB backend (UWB_BACKEND=qani).
 *
 * Full session lifecycle ported from the Qorvo reference implementation:
 *   fira_niq.c    — session start/stop sequencing
 *   common_fira.c — parameter mapping, measurement sequence
 *   fira_dw3000.c — platform/MCPS init
 *
 * This file is the ONLY Qorvo-API-aware file in our tree.
 */
#include "uwb_port.h"
#include "nrf_log.h"

#include "niq.h"
#include "uwbmac/uwbmac.h"
#include "uwbmac/fira_helper.h"
#include "common_fira.h"
#include "llhw.h"

#include "nrf_soc.h"

#include <string.h>
#include <stdlib.h>

/* ---- crypto callbacks for niq_init ---- */

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

/* ---- constants ---- */

#define ACCESSORY_RANGING_ROLE 0  /* Controlee+Responder */
#define CONN_ID                0
#define FIRA_ROLE_MASK         0x01
#define BPRF_SET_2             2
#define AR2U16(x)              (((x)[1] << 8) | (x)[0])

/* ---- state ---- */

static uwb_port_evt_cb_t      m_cb;
static struct uwbmac_context  *m_uwbmac_ctx;
static struct fira_context     m_fira_ctx;
static uint32_t                m_session_id;
static uint32_t                m_session_handle;
static bool                    m_ranging_active;
static uwb_port_range_t        m_last_range;

/* Result buffer for fira_helper callback (JSON in reference, we just
 * extract the numbers). */
static char m_result_buf[256];
static struct {
    char    *str;
    uint16_t len;
} m_output_result;

/* fira_device_configure_t populated by niq_configure_and_start_uwb from
 * the phone's shareable config. Defaults match ble_niq.c. */
static fira_device_configure_t m_fira_config = {
    .role                           = 0,
    .enc_payload                    = 1,
    .Session_ID                     = 1111,
    .Ranging_Round_Usage            = 3,
    .Multi_Node_Mode                = 0,
    .Rframe_Config                  = 3,
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
    .SP0_PHY_Set                    = 2,
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

/* ---- parameter mapping (ported from fira_niq.c fira_set_params) ---- */

static void map_fira_params(struct session_parameters *sp,
                            fira_device_configure_t *cfg,
                            bool is_controller,
                            uint16_t *out_short_addr)
{
    memset(sp, 0, sizeof(*sp));

    *out_short_addr = AR2U16(cfg->SRC_ADDR);

    if (is_controller) {
        sp->device_type = QUWBS_FBS_DEVICE_TYPE_CONTROLLER;
        sp->device_role = QUWBS_FBS_DEVICE_ROLE_INITIATOR;
    } else {
        sp->device_type = QUWBS_FBS_DEVICE_TYPE_CONTROLEE;
        sp->device_role = QUWBS_FBS_DEVICE_ROLE_RESPONDER;
    }

    sp->ranging_round_usage = cfg->Ranging_Round_Usage;
    sp->rframe_config       = cfg->Rframe_Config;
    sp->sfd_id = (cfg->SP0_PHY_Set == BPRF_SET_2)
                     ? FIRA_SFD_ID_2 : FIRA_SFD_ID_0;
    sp->slot_duration_rstu  = cfg->Slot_Duration_RSTU;
    sp->block_duration_ms   = cfg->Block_Duration_ms;
    sp->round_duration_slots =
        1 + cfg->Round_Duration_RSTU / cfg->Slot_Duration_RSTU;
    sp->multi_node_mode     = cfg->Multi_Node_Mode;
    sp->preamble_duration   = FIRA_PREAMBLE_DURATION_64;
    sp->ranging_round_control |=
        fira_helper_bool_to_ranging_round_control(true, false);
    sp->round_hopping       = cfg->Round_Hopping;
    sp->result_report_config |=
        fira_helper_bool_to_result_report_config(
            (bool)(cfg->ToF_Report > 0), false, false, false);

    sp->short_addr = AR2U16(cfg->SRC_ADDR);
    sp->destination_short_address[0] = AR2U16(cfg->DST_ADDR);
    sp->n_destination_short_address  = 1;

    sp->schedule_mode = FIRA_SCHEDULE_MODE_TIME_SCHEDULED;

    sp->vupper64[7] = cfg->Vendor_ID[0];
    sp->vupper64[6] = cfg->Vendor_ID[1];
    sp->vupper64[5] = cfg->Static_STS_IV[0];
    sp->vupper64[4] = cfg->Static_STS_IV[1];
    sp->vupper64[3] = cfg->Static_STS_IV[2];
    sp->vupper64[2] = cfg->Static_STS_IV[3];
    sp->vupper64[1] = cfg->Static_STS_IV[4];
    sp->vupper64[0] = cfg->Static_STS_IV[5];

    sp->channel_number      = cfg->Channel_Number;
    sp->preamble_code_index = cfg->Preamble_Code;
    sp->number_of_sts_segments = FIRA_STS_SEGMENTS_1;
    sp->sts_length          = FIRA_STS_LENGTH_64;

    /* Measurement sequence — range only (DWM3001CDK has no AoA antenna). */
    sp->meas_seq.n_steps = 1;
    sp->meas_seq.steps[0].type = FIRA_MEASUREMENT_TYPE_RANGE;
    sp->meas_seq.steps[0].n_measurements = 1;
    sp->meas_seq.steps[0].rx_ant_set_nonranging     = 0xff;
    sp->meas_seq.steps[0].rx_ant_sets_ranging[0]     = 0xff;
    sp->meas_seq.steps[0].rx_ant_sets_ranging[1]     = 0xff;
    sp->meas_seq.steps[0].tx_ant_set_nonranging      = 0xff;
    sp->meas_seq.steps[0].tx_ant_set_ranging          = 0xff;
}

/* ---- set all session parameters (ported from common_fira.c) ---- */

static enum qerr set_all_session_params(struct fira_context *ctx,
                                        uint32_t handle,
                                        struct session_parameters *sp)
{
    enum qerr r;

#define SET(param)                                                        \
    do {                                                                  \
        r = fira_helper_set_session_##param(ctx, handle, sp->param);     \
        if (r) return r;                                                  \
    } while (0)

    SET(channel_number);
    SET(preamble_code_index);
    SET(sfd_id);
    SET(phr_data_rate);
    SET(prf_mode);
    SET(device_type);
    SET(device_role);
    SET(multi_node_mode);
    SET(rframe_config);
    SET(slot_duration_rstu);
    SET(block_duration_ms);
    SET(round_duration_slots);
    SET(ranging_round_usage);
    SET(round_hopping);
    SET(block_stride_length);
    SET(schedule_mode);
    SET(vupper64);
    SET(result_report_config);
    SET(ranging_round_control);
    SET(enable_diagnostics);
    SET(report_rssi);
#undef SET

    r = fira_helper_set_session_short_address(ctx, handle, sp->short_addr);
    if (r) return r;

    r = fira_helper_set_session_destination_short_addresses(
            ctx, handle,
            sp->n_destination_short_address,
            sp->destination_short_address);
    if (r) return r;

    r = fira_helper_set_session_measurement_sequence(
            ctx, handle, &sp->meas_seq);
    if (r) return r;

    r = fira_helper_set_session_diags_frame_reports_fields(
            ctx, handle,
            FIRA_RANGING_DIAGNOSTICS_FRAME_REPORT_SEGMENT_METRICS |
            FIRA_RANGING_DIAGNOSTICS_FRAME_REPORT_CFO);

    return r;
}

/* ---- ranging results callback (from fira_helper) ---- */

static void on_range_result(const struct fira_twr_ranging_results *results,
                            void *user_data)
{
    (void)user_data;

    if (results->n_measurements == 0)
        return;

    const struct fira_twr_measurements *rm = &results->measurements[0];

    if (rm->status != 0) {
        m_last_range.valid = false;
        NRF_LOG_INFO("uwb: range err (status %u)", rm->status);
        return;
    }

    m_last_range.distance_cm     = rm->distance_cm;
    m_last_range.azimuth_deg_q7  = rm->local_aoa_measurements[0].aoa_2pi;
    m_last_range.aoa_fom         = rm->local_aoa_measurements[0].aoa_fom_100;
    m_last_range.elevation_deg_q7 = INT16_MIN;
    m_last_range.valid           = true;

    NRF_LOG_INFO("uwb: range %d cm", (int)rm->distance_cm);

    if (m_cb) {
        m_cb(UWB_PORT_EVT_RANGE);
    }
}

static void on_fira_event(enum fira_helper_cb_type cb_type,
                          const void *content,
                          void *user_data)
{
    switch (cb_type) {
    case FIRA_HELPER_CB_TYPE_TWR_RANGE_NTF:
        on_range_result(
            (const struct fira_twr_ranging_results *)content, user_data);
        break;
    default:
        break;
    }
}

/* ---- session lifecycle (ported from fira_niq.c) ---- */

static int fira_session_start(void)
{
    bool is_controller = m_fira_config.role & FIRA_ROLE_MASK;
    struct session_parameters sp;
    uint16_t short_addr;
    struct fbs_session_init_rsp rsp;
    enum qerr r;

    map_fira_params(&sp, &m_fira_config, is_controller, &short_addr);
    m_session_id = m_fira_config.Session_ID;

    m_output_result.str = m_result_buf;
    m_output_result.len = sizeof(m_result_buf);

    uwbmac_set_promiscuous_mode(m_uwbmac_ctx, true);
    uwbmac_set_short_addr(m_uwbmac_ctx, short_addr);

    r = fira_helper_open(&m_fira_ctx, m_uwbmac_ctx,
                         &on_fira_event, "endless", 0,
                         &m_output_result);
    if (r != QERR_SUCCESS) {
        NRF_LOG_ERROR("uwb: fira_helper_open failed (%d)", r);
        return -1;
    }

    r = fira_helper_set_scheduler(&m_fira_ctx);
    if (r != QERR_SUCCESS) {
        NRF_LOG_ERROR("uwb: set_scheduler failed (%d)", r);
        goto err_close;
    }

    r = fira_helper_init_session(
            &m_fira_ctx, m_session_id,
            QUWBS_FBS_SESSION_TYPE_RANGING_NO_IN_BAND_DATA,
            &rsp);
    if (r != QERR_SUCCESS) {
        NRF_LOG_ERROR("uwb: init_session failed (%d)", r);
        goto err_close;
    }
    m_session_handle = rsp.session_handle;

    r = set_all_session_params(&m_fira_ctx, m_session_handle, &sp);
    if (r != QERR_SUCCESS) {
        NRF_LOG_ERROR("uwb: set_session_params failed (%d)", r);
        goto err_deinit;
    }

    if (is_controller) {
        struct controlees_parameters cp;
        memset(&cp, 0, sizeof(cp));
        cp.n_controlees = m_fira_config.Number_of_Controlee;
        cp.controlees[0].address = sp.destination_short_address[0];
        r = fira_helper_add_controlee(&m_fira_ctx, m_session_handle,
                                      (const struct controlee_parameters *)&cp);
        if (r != QERR_SUCCESS) {
            NRF_LOG_ERROR("uwb: add_controlee failed (%d)", r);
            goto err_deinit;
        }
    }

    r = uwbmac_start(m_uwbmac_ctx);
    if (r != QERR_SUCCESS) {
        NRF_LOG_ERROR("uwb: uwbmac_start failed (%d)", r);
        goto err_deinit;
    }

    r = fira_helper_start_session(&m_fira_ctx, m_session_handle);
    if (r != QERR_SUCCESS) {
        NRF_LOG_ERROR("uwb: start_session failed (%d)", r);
        uwbmac_stop(m_uwbmac_ctx);
        goto err_deinit;
    }

    m_ranging_active = true;
    NRF_LOG_INFO("uwb: ranging started (session %u, ch %u)",
                 m_session_id, m_fira_config.Channel_Number);
    return 0;

err_deinit:
    fira_helper_deinit_session(&m_fira_ctx, m_session_handle);
err_close:
    fira_helper_close(&m_fira_ctx);
    return -1;
}

static void fira_session_stop(void)
{
    if (!m_ranging_active)
        return;

    uwbmac_stop(m_uwbmac_ctx);
    fira_helper_stop_session(&m_fira_ctx, m_session_handle);
    fira_helper_deinit_session(&m_fira_ctx, m_session_handle);
    fira_helper_close(&m_fira_ctx);

    m_ranging_active = false;
    NRF_LOG_INFO("uwb: ranging stopped");
}

/* ---- niq_init callbacks ---- */

static volatile bool m_start_pending;
static volatile bool m_stop_pending;

static void on_niq_start_uwb(fira_device_configure_t *config, void *user_ctx)
{
    (void)user_ctx;
    NRF_LOG_INFO("uwb: niq requests start (session %u, ch %u)",
                 config->Session_ID, config->Channel_Number);
    m_start_pending = true;
}

static void on_niq_stop_uwb(uint32_t session_id, void *user_ctx)
{
    (void)user_ctx;
    NRF_LOG_INFO("uwb: niq requests stop (session %u)", session_id);
    m_stop_pending = true;
}

/* ---- public API ---- */

int uwb_port_init(uwb_port_evt_cb_t cb)
{
    m_cb = cb;

    /* Initialize UWB hardware: platform → llhw → uwbmac */
    enum qerr r = fira_uwb_mcps_init(&m_uwbmac_ctx);
    if (r != QERR_SUCCESS) {
        NRF_LOG_ERROR("uwb: fira_uwb_mcps_init failed (%d)", r);
        return -1;
    }

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

    NRF_LOG_INFO("uwb: QANI backend initialised (niq v2.1, uwbmac ready)");
    return 0;
}

int uwb_port_get_accessory_config(uint8_t *buf, uint16_t *len)
{
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
    return ret;
}

int uwb_port_stop(void)
{
    int ret = niq_stop_uwb(CONN_ID, NULL);
    return ret;
}

bool uwb_port_poll(void)
{
    bool did_work = false;

    if (m_start_pending) {
        m_start_pending = false;
        did_work = true;
        if (fira_session_start() == 0) {
            if (m_cb) m_cb(UWB_PORT_EVT_STARTED);
        } else {
            if (m_cb) m_cb(UWB_PORT_EVT_ERROR);
        }
    }

    if (m_stop_pending) {
        m_stop_pending = false;
        did_work = true;
        fira_session_stop();
        if (m_cb) m_cb(UWB_PORT_EVT_STOPPED);
    }

    /* Process pending uwbmac events (IRQ-driven ranging rounds). */
    if (m_ranging_active && m_uwbmac_ctx) {
        enum qerr r = uwbmac_poll_events(m_uwbmac_ctx, 0);
        if (r == QERR_SUCCESS) {
            did_work = true;
        }
    }

    return did_work;
}

const uwb_port_range_t *uwb_port_last_range(void)
{
    return &m_last_range;
}
