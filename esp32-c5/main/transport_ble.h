#pragma once

#include <stdint.h>

void transport_ble_init(void);

/* Number of currently active BLE GATT connections (0 if no client paired). */
uint32_t transport_ble_connected_count(void);
