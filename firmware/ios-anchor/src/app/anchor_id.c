#include "anchor_id.h"
#include "nrf52.h"
#include <stdio.h>
#include <string.h>

static char m_label[ANCHOR_LABEL_MAX_LEN + 1];
static char m_adv_name[12];
static bool m_loaded;

static void load(void)
{
    if (m_loaded) {
        return;
    }
    m_loaded = true;

    uint8_t id = anchor_id_get();

    const volatile uint8_t *p = (const volatile uint8_t *)&NRF_UICR->CUSTOMER[4];
    uint8_t n = 0;
    while (n < ANCHOR_LABEL_MAX_LEN && p[n] != 0xFF && p[n] != 0x00) {
        m_label[n] = (char)p[n];
        n++;
    }
    m_label[n] = '\0';

    if (id == ANCHOR_ID_UNPROVISIONED) {
        snprintf(m_adv_name, sizeof(m_adv_name), "InZone-Ax");
        if (n == 0) {
            strcpy(m_label, "InZone-unset");
        }
    } else {
        snprintf(m_adv_name, sizeof(m_adv_name), "InZone-A%u", id);
        if (n == 0) {
            strcpy(m_label, m_adv_name);
        }
    }
}

uint8_t anchor_id_get(void)
{
    uint32_t raw = NRF_UICR->CUSTOMER[0];
    return (raw > 3) ? ANCHOR_ID_UNPROVISIONED : (uint8_t)raw;
}

const char *anchor_label_get(void)
{
    load();
    return m_label;
}

const char *anchor_adv_name_get(void)
{
    load();
    return m_adv_name;
}
