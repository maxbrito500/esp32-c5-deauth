#pragma once

#include <stdint.h>
#include <stdbool.h>

#define MAC_LEN 6

extern const uint8_t MAC_BROADCAST[MAC_LEN];

/* Send a single deauth frame.
 * da     = destination (STA mac for unicast, FF:FF:FF:FF:FF:FF for broadcast)
 * bssid  = AP's BSSID (also used as SA, spoofing the AP)
 * reason = 802.11 reason code (1, 3, 6, 7, 8 are typical)
 */
void frames_send_deauth(const uint8_t *da, const uint8_t *bssid, uint16_t reason);

/* Disassoc — same shape as deauth, different subtype. */
void frames_send_disassoc(const uint8_t *da, const uint8_t *bssid, uint16_t reason);

/* Auth flood: forge open-system auth requests from random SAs to a target AP.
 * Fills the AP's auth table; works as a noise/auth-flood attack. */
void frames_send_auth_flood(const uint8_t *bssid);

/* Bursts (calls esp_wifi_set_channel first). Returns frames sent. */
uint32_t frames_burst_deauth(uint8_t channel, const uint8_t *da, const uint8_t *bssid);
uint32_t frames_burst_disassoc(uint8_t channel, const uint8_t *da, const uint8_t *bssid);
uint32_t frames_burst_auth_flood(uint8_t channel, const uint8_t *bssid);
