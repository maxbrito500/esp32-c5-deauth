#pragma once

#include <stdint.h>
#include <stdbool.h>

/* Run a blocking promiscuous capture for `seconds` on the given channel,
 * filtered to packets involving `bssid`. Discovered STAs are added to
 * targets via targets_add_sta(). */
int sniffer_run(uint8_t channel, const uint8_t *bssid, uint32_t seconds);
