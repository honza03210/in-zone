#include "cli.h"
#include "anchor_id.h"
#include "leds.h"
#include "ble_stack.h"
#include "ni_protocol.h"
#include "uwb_port.h"
#include "board_dwm3001cdk.h"

#include "SEGGER_RTT.h"
#include "app_timer.h"
#include "app_error.h"
#include "nrf_gpio.h"
#include "nrf_delay.h"
#include "nrf.h"

#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#define CLI_LINE_MAX 32

/* DW3110 SPI pins (DWM3001CDK module wiring, same as the QANI config in the
 * Makefile / Qorvo's uwb_stack_llhw.cmake). NOTE: CS is on PORT 1 (P1.06) —
 * the other SPI lines are port 0. Only used by the bit-banged `spi` probe. */
#define DW_SCK_PIN   NRF_GPIO_PIN_MAP(0, 3)
#define DW_MOSI_PIN  NRF_GPIO_PIN_MAP(0, 8)
#define DW_MISO_PIN  NRF_GPIO_PIN_MAP(0, 29)
#define DW_CS_PIN    NRF_GPIO_PIN_MAP(1, 6)
#define DW_RSTN_PIN  NRF_GPIO_PIN_MAP(0, 25)

static char     m_line[CLI_LINE_MAX];
static uint8_t  m_line_len;
static uint32_t m_uptime_s;

APP_TIMER_DEF(m_tick_timer);

#define cli_printf(...) (void)SEGGER_RTT_printf(0, __VA_ARGS__)

static void tick_handler(void *ctx)
{
    (void)ctx;
    m_uptime_s++;
}

/* ------------------------------------------------------------------ */
/* DW3110 SPI probe (bit-banged, mode 0, MSB first)                    */
/*                                                                     */
/* Bit-banging instead of SPIM3 so the probe works identically in the  */
/* stub build (no SPI driver at all) and the QANI build before the     */
/* UWB stack initialises. Once a NI session has started, SPIM3 owns    */
/* the pins and the probe refuses to run.                              */
/* ------------------------------------------------------------------ */

static uint8_t spi_xfer_byte(uint8_t out)
{
    uint8_t in = 0;
    for (int bit = 7; bit >= 0; bit--) {
        nrf_gpio_pin_write(DW_MOSI_PIN, (out >> bit) & 1);
        nrf_delay_us(1);
        nrf_gpio_pin_set(DW_SCK_PIN);
        in = (uint8_t)((in << 1) | nrf_gpio_pin_read(DW_MISO_PIN));
        nrf_delay_us(1);
        nrf_gpio_pin_clear(DW_SCK_PIN);
    }
    return in;
}

/* The QM33/DW3110 powers up in SLEEP and ignores SPI until woken: hold CS
 * low >400 us, raise it, then wait ~500 us for it to reach IDLE_RC. Mirrors
 * qpwr_uwb_wakeup() (WAKEUP_CS_TOGGLE_US / WAKEUP_DELAY_US) in the Qorvo SDK. */
static void dw_wakeup(void)
{
    nrf_gpio_pin_clear(DW_CS_PIN);
    nrf_delay_us(400);
    nrf_gpio_pin_set(DW_CS_PIN);
    nrf_delay_us(500);
}

static uint32_t dw_read_dev_id(void)
{
    nrf_gpio_pin_clear(DW_CS_PIN);
    nrf_delay_us(1);

    /* Short-addressed read of register file 0x00: DEV_ID, 4 bytes LSB first */
    spi_xfer_byte(0x00);
    uint32_t id = 0;
    for (int i = 0; i < 4; i++) {
        id |= (uint32_t)spi_xfer_byte(0x00) << (8 * i);
    }

    nrf_gpio_pin_set(DW_CS_PIN);
    return id;
}

static void cmd_spi(void)
{
    if (ni_protocol_state() != NI_STATE_IDLE) {
        cli_printf("spi: refused, NI session active (SPIM3 owns the bus)\r\n");
        return;
    }

    nrf_gpio_cfg_output(DW_SCK_PIN);
    nrf_gpio_cfg_output(DW_MOSI_PIN);
    nrf_gpio_cfg_output(DW_CS_PIN);
    nrf_gpio_cfg_input(DW_MISO_PIN, NRF_GPIO_PIN_PULLDOWN);
    nrf_gpio_pin_clear(DW_SCK_PIN);
    nrf_gpio_pin_set(DW_CS_PIN);
    nrf_delay_us(10);

    dw_wakeup(); /* DW3110 boots asleep; must wake it before SPI responds */
    uint32_t id = dw_read_dev_id();

    if ((id >> 16) != 0xDECA) {
        /* Maybe held in reset; pulse RSTN (open-drain low pulse, never
         * drive high), wake again, and retry once. */
        cli_printf("spi: DEV_ID=0x%08x invalid, pulsing RSTN...\r\n", id);
        nrf_gpio_cfg_output(DW_RSTN_PIN);
        nrf_gpio_pin_clear(DW_RSTN_PIN);
        nrf_delay_ms(1);
        nrf_gpio_cfg_default(DW_RSTN_PIN); /* release, chip pulls high */
        nrf_delay_ms(5);                   /* wait for IDLE_RC */
        dw_wakeup();
        id = dw_read_dev_id();
    }

    /* Release the pins so a later QANI init starts from a clean slate */
    nrf_gpio_cfg_default(DW_SCK_PIN);
    nrf_gpio_cfg_default(DW_MOSI_PIN);
    nrf_gpio_cfg_default(DW_MISO_PIN);
    nrf_gpio_cfg_default(DW_CS_PIN);

    if ((id >> 16) == 0xDECA) {
        cli_printf("spi: DEV_ID=0x%08x OK (DW3xxx, rev 0x%04x)\r\n",
                   id, id & 0xFFFF);
    } else {
        cli_printf("spi: DEV_ID=0x%08x FAIL (expected 0xDECAxxxx)\r\n", id);
        cli_printf("     all-0x00/0xFF suggests a wiring/power issue\r\n");
    }
}

/* ------------------------------------------------------------------ */
/* Other commands                                                      */
/* ------------------------------------------------------------------ */

static const char *ni_state_str(void)
{
    switch (ni_protocol_state()) {
    case NI_STATE_IDLE:       return "idle";
    case NI_STATE_CONFIGURED: return "configured";
    case NI_STATE_RANGING:    return "ranging";
    default:                  return "?";
    }
}

static void cmd_status(void)
{
    cli_printf("build:   %s %s (%s backend)\r\n", __DATE__, __TIME__,
#ifdef UWB_BACKEND_QANI
               "qani"
#else
               "stub"
#endif
    );
    cli_printf("uptime:  %u s\r\n", (unsigned)m_uptime_s);
    cli_printf("anchor:  id=%u label=\"%s\" adv=\"%s\"\r\n",
               anchor_id_get(), anchor_label_get(), anchor_adv_name_get());
    cli_printf("ble:     %s\r\n",
               ble_stack_is_connected() ? "connected" : "advertising");
    cli_printf("ni:      %s\r\n", ni_state_str());

    const uwb_port_range_t *r = uwb_port_last_range();
    if (r != NULL && r->valid) {
        cli_printf("range:   %d cm (fom %u)\r\n",
                   (int)r->distance_cm, r->aoa_fom);
    } else {
        cli_printf("range:   none\r\n");
    }
}

static void cmd_uicr(void)
{
    cli_printf("UICR.CUSTOMER[0] @0x10001080 = 0x%08x (anchor id)\r\n",
               (unsigned)NRF_UICR->CUSTOMER[0]);
    cli_printf("UICR.CUSTOMER[4..7] (label):");
    for (int i = 4; i <= 7; i++) {
        cli_printf(" %08x", (unsigned)NRF_UICR->CUSTOMER[i]);
    }
    cli_printf("\r\n");
    cli_printf("decoded: id=%u label=\"%s\"\r\n",
               anchor_id_get(), anchor_label_get());
}

static void cmd_led(const char *arg)
{
    if (arg == NULL) {
        cli_printf("usage: led <boot|adv|conn|range|err|id>\r\n");
    } else if (strcmp(arg, "boot") == 0) {
        leds_set_state(LEDS_STATE_BOOT);
    } else if (strcmp(arg, "adv") == 0) {
        leds_set_state(LEDS_STATE_ADVERTISING);
    } else if (strcmp(arg, "conn") == 0) {
        leds_set_state(LEDS_STATE_CONNECTED);
    } else if (strcmp(arg, "range") == 0) {
        leds_set_state(LEDS_STATE_RANGING);
    } else if (strcmp(arg, "err") == 0) {
        leds_set_state(LEDS_STATE_ERROR);
    } else if (strcmp(arg, "id") == 0) {
        leds_identify(5);
    } else {
        cli_printf("led: unknown state \"%s\"\r\n", arg);
        return;
    }
    cli_printf("led: %s\r\n", arg);
    /* Note: the main loop's update_leds() will reassert the real state
     * on the next BLE/NI change; this is for visual pin checks. */
}

static void cmd_help(void)
{
    cli_printf("In-Zone anchor bring-up console\r\n");
    cli_printf("  status      boot/BLE/NI/ranging summary\r\n");
    cli_printf("  spi         probe DW3110 DEV_ID over bit-banged SPI\r\n");
    cli_printf("  uicr        dump provisioned identity registers\r\n");
    cli_printf("  led <s>     force LED state (boot|adv|conn|range|err|id)\r\n");
    cli_printf("  reset       reboot the MCU\r\n");
}

static void dispatch(char *line)
{
    char *cmd = strtok(line, " ");
    if (cmd == NULL) {
        return;
    }
    char *arg = strtok(NULL, " ");

    if (strcmp(cmd, "help") == 0) {
        cmd_help();
    } else if (strcmp(cmd, "status") == 0) {
        cmd_status();
    } else if (strcmp(cmd, "spi") == 0) {
        cmd_spi();
    } else if (strcmp(cmd, "uicr") == 0) {
        cmd_uicr();
    } else if (strcmp(cmd, "led") == 0) {
        cmd_led(arg);
    } else if (strcmp(cmd, "reset") == 0) {
        cli_printf("resetting...\r\n");
        nrf_delay_ms(10); /* let RTT flush */
        NVIC_SystemReset();
    } else {
        cli_printf("unknown command \"%s\", try `help`\r\n", cmd);
    }
}

/* ------------------------------------------------------------------ */

void cli_init(void)
{
    APP_ERROR_CHECK(app_timer_create(&m_tick_timer, APP_TIMER_MODE_REPEATED,
                                     tick_handler));
    APP_ERROR_CHECK(app_timer_start(m_tick_timer, APP_TIMER_TICKS(1000), NULL));
    cli_printf("cli: ready, type `help`\r\n");
}

void cli_poll(void)
{
    int c;
    while ((c = SEGGER_RTT_GetKey()) >= 0) {
        if (c == '\r' || c == '\n') {
            cli_printf("\r\n");
            if (m_line_len > 0) {
                m_line[m_line_len] = '\0';
                dispatch(m_line);
                m_line_len = 0;
            }
            cli_printf("> ");
        } else if (c == 0x08 || c == 0x7F) { /* backspace */
            if (m_line_len > 0) {
                m_line_len--;
                cli_printf("\b \b");
            }
        } else if (c >= 0x20 && c < 0x7F && m_line_len < CLI_LINE_MAX - 1) {
            m_line[m_line_len++] = (char)c;
            cli_printf("%c", c);
        }
    }
}
