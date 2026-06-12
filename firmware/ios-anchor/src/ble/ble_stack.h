#ifndef INZONE_BLE_STACK_H
#define INZONE_BLE_STACK_H

#include <stdbool.h>

/* Connection state changes, surfaced to the app for LEDs/cleanup. */
typedef void (*ble_stack_conn_cb_t)(bool connected);

/* Initialises SoftDevice, GAP/GATT params (MTU 247), both In-Zone
 * services, and advertising. Advertising restarts automatically on
 * disconnect (fast session re-arm for the round-robin scheduler). */
void ble_stack_init(ble_stack_conn_cb_t conn_cb);

void ble_stack_advertising_start(void);

bool ble_stack_is_connected(void);

#endif
