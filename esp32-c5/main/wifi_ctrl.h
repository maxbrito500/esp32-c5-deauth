#pragma once

#include <stdint.h>
#include <stdbool.h>

#include "esp_wifi.h"

#define WIFI_SCAN_MAX_APS 64

void wifi_ctrl_init(void);

/* Triggers a blocking dual-band scan, populates targets_t aps[]. */
int wifi_ctrl_scan(void);

/* Set channel (1-14 for 2.4 GHz, 36+ for 5 GHz). */
void wifi_ctrl_set_channel(uint8_t channel);
