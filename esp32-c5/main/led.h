#pragma once

/* RGB LED status indicator.
 *
 * Pulses the on-board WS2812 LED every 5 seconds. Color reflects the
 * current state, queried automatically from transport_ble + attack:
 *   - GREEN  : idle (no BLE client connected)
 *   - BLUE   : a BLE client is connected
 *   - RED    : an attack is currently running
 */
void led_init(void);
