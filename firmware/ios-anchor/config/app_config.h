/*
 * In-Zone overrides applied on top of sdk_config.h (the nRF5 SDK
 * include chain picks this up when -DUSE_APP_CONFIG is defined).
 * Base sdk_config.h: copy from
 *   <SDK>/examples/ble_peripheral/ble_app_uart/pca10100/s113/config/
 * (pca10100 = nRF52833 DK, same SoC as the DWM3001C module).
 */
#ifndef APP_CONFIG_H
#define APP_CONFIG_H

/* BLE */
#define NRF_SDH_BLE_GATT_MAX_MTU_SIZE 247  /* NI config blobs in one PDU */
#define NRF_SDH_BLE_VS_UUID_COUNT     1
#define NRF_SDH_BLE_PERIPHERAL_LINK_COUNT 1
#define NRF_SDH_BLE_CENTRAL_LINK_COUNT    0
#define NRF_SDH_BLE_GAP_DATA_LENGTH   251

/* Modules used beyond the ble_app_uart defaults */
#define BLE_ADVERTISING_ENABLED 1
#define NRF_CLOCK_ENABLED       1
#define NRFX_WDT_ENABLED        1
#define WDT_ENABLED             1
#define NRF_PWR_MGMT_ENABLED    1

/* DWM3001CDK has a 32.768 kHz crystal */
#define NRF_SDH_CLOCK_LF_SRC        1 /* XTAL */
#define NRF_SDH_CLOCK_LF_RC_CTIV    0
#define NRF_SDH_CLOCK_LF_RC_TEMP_CTIV 0
#define NRF_SDH_CLOCK_LF_ACCURACY   7 /* 20 ppm */

/* Logging over SEGGER RTT (J-Link is on board) */
#define NRF_LOG_ENABLED             1
#define NRF_LOG_BACKEND_RTT_ENABLED 1
#define NRF_LOG_BACKEND_UART_ENABLED 0
#define NRF_LOG_DEFAULT_LEVEL       3 /* info */

#endif /* APP_CONFIG_H */
