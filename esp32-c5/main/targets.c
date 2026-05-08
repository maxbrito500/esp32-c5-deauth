#include "targets.h"

#include <string.h>
#include <strings.h>
#include <stdio.h>

#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

#include "io.h"

static SemaphoreHandle_t s_mutex;

static target_ap_t  s_aps[TARGETS_MAX_APS];
static int          s_ap_count = 0;

static target_sta_t s_stas[TARGETS_MAX_STAS];
static int          s_sta_count = 0;

static target_ap_t  s_sel_24;
static bool         s_has_sel_24 = false;
static target_ap_t  s_sel_5;
static bool         s_has_sel_5 = false;
static target_sta_t s_sel_sta;
static bool         s_has_sel_sta = false;

static attack_mode_t s_mode = ATTACK_MODE_BROADCAST;

#define LOCK()   xSemaphoreTake(s_mutex, portMAX_DELAY)
#define UNLOCK() xSemaphoreGive(s_mutex)

void targets_init(void)
{
    s_mutex = xSemaphoreCreateMutex();
}

void targets_set_aps(const target_ap_t *aps, uint16_t n)
{
    LOCK();
    if (n > TARGETS_MAX_APS) n = TARGETS_MAX_APS;
    s_ap_count = n;
    if (aps && n) memcpy(s_aps, aps, n * sizeof(target_ap_t));
    UNLOCK();
}

int targets_get_ap(uint16_t idx, target_ap_t *out)
{
    int rc = -1;
    LOCK();
    if (idx < s_ap_count) {
        *out = s_aps[idx];
        rc = 0;
    }
    UNLOCK();
    return rc;
}

int targets_ap_count(void)
{
    LOCK();
    int c = s_ap_count;
    UNLOCK();
    return c;
}

void targets_list_aps(void)
{
    LOCK();
    int n = s_ap_count;
    if (n == 0) {
        UNLOCK();
        io_log("(no APs — run `scan` first)\r\n");
        return;
    }
    io_log("idx  ch  band   rssi  bssid              ssid\r\n");
    for (int i = 0; i < n; i++) {
        const target_ap_t *a = &s_aps[i];
        io_log("%3d  %2u  %s  %4d  %02X:%02X:%02X:%02X:%02X:%02X  %s\r\n",
               i, (unsigned)a->channel, a->band_5ghz ? "5GHz " : "2.4GHz",
               (int)a->rssi,
               a->bssid[0], a->bssid[1], a->bssid[2],
               a->bssid[3], a->bssid[4], a->bssid[5],
               a->ssid);
    }
    UNLOCK();
}

void targets_clear_stas(void)
{
    LOCK();
    s_sta_count = 0;
    UNLOCK();
}

bool targets_add_sta(const uint8_t *mac, const uint8_t *bssid, uint8_t channel, int8_t rssi)
{
    LOCK();
    /* dedupe by mac */
    for (int i = 0; i < s_sta_count; i++) {
        if (memcmp(s_stas[i].mac, mac, 6) == 0) {
            s_stas[i].rssi = rssi;
            s_stas[i].channel = channel;
            if (bssid) memcpy(s_stas[i].bssid, bssid, 6);
            UNLOCK();
            return false;
        }
    }
    if (s_sta_count >= TARGETS_MAX_STAS) {
        UNLOCK();
        return false;
    }
    target_sta_t *s = &s_stas[s_sta_count++];
    memcpy(s->mac, mac, 6);
    if (bssid) memcpy(s->bssid, bssid, 6); else memset(s->bssid, 0, 6);
    s->channel = channel;
    s->rssi = rssi;
    UNLOCK();
    return true;
}

int targets_get_sta(uint16_t idx, target_sta_t *out)
{
    int rc = -1;
    LOCK();
    if (idx < s_sta_count) {
        *out = s_stas[idx];
        rc = 0;
    }
    UNLOCK();
    return rc;
}

int targets_sta_count(void)
{
    LOCK();
    int c = s_sta_count;
    UNLOCK();
    return c;
}

void targets_list_stas(void)
{
    LOCK();
    int n = s_sta_count;
    if (n == 0) {
        UNLOCK();
        io_log("(no STAs — run `sniff <ap_idx> <sec>` first)\r\n");
        return;
    }
    io_log("idx  ch  rssi  sta-mac            bssid\r\n");
    for (int i = 0; i < n; i++) {
        const target_sta_t *s = &s_stas[i];
        io_log("%3d  %2u  %4d  %02X:%02X:%02X:%02X:%02X:%02X  %02X:%02X:%02X:%02X:%02X:%02X\r\n",
               i, (unsigned)s->channel, (int)s->rssi,
               s->mac[0], s->mac[1], s->mac[2], s->mac[3], s->mac[4], s->mac[5],
               s->bssid[0], s->bssid[1], s->bssid[2], s->bssid[3], s->bssid[4], s->bssid[5]);
    }
    UNLOCK();
}

int targets_select_24(uint16_t ap_idx)
{
    int rc = -2;
    LOCK();
    if (ap_idx < s_ap_count) {
        if (s_aps[ap_idx].band_5ghz) {
            rc = -1;
        } else {
            s_sel_24 = s_aps[ap_idx];
            s_has_sel_24 = true;
            rc = 0;
        }
    }
    UNLOCK();
    return rc;
}

int targets_select_5(uint16_t ap_idx)
{
    int rc = -2;
    LOCK();
    if (ap_idx < s_ap_count) {
        if (!s_aps[ap_idx].band_5ghz) {
            rc = -1;
        } else {
            s_sel_5 = s_aps[ap_idx];
            s_has_sel_5 = true;
            rc = 0;
        }
    }
    UNLOCK();
    return rc;
}

int targets_select_sta(uint16_t sta_idx)
{
    int rc = -2;
    LOCK();
    if (sta_idx < s_sta_count) {
        s_sel_sta = s_stas[sta_idx];
        s_has_sel_sta = true;
        rc = 0;
    }
    UNLOCK();
    return rc;
}

void targets_clear_selection(void)
{
    LOCK();
    s_has_sel_24 = false;
    s_has_sel_5 = false;
    s_has_sel_sta = false;
    UNLOCK();
}

bool targets_get_selected_24(target_ap_t *out)
{
    LOCK();
    bool r = s_has_sel_24;
    if (r) *out = s_sel_24;
    UNLOCK();
    return r;
}

bool targets_get_selected_5(target_ap_t *out)
{
    LOCK();
    bool r = s_has_sel_5;
    if (r) *out = s_sel_5;
    UNLOCK();
    return r;
}

bool targets_get_selected_sta(target_sta_t *out)
{
    LOCK();
    bool r = s_has_sel_sta;
    if (r) *out = s_sel_sta;
    UNLOCK();
    return r;
}

void targets_set_mode(attack_mode_t m)
{
    LOCK();
    s_mode = m;
    UNLOCK();
}

attack_mode_t targets_get_mode(void)
{
    LOCK();
    attack_mode_t m = s_mode;
    UNLOCK();
    return m;
}

const char *targets_mode_name(attack_mode_t m)
{
    switch (m) {
        case ATTACK_MODE_BROADCAST: return "broadcast";
        case ATTACK_MODE_UNICAST:   return "unicast";
        case ATTACK_MODE_DISASSOC:  return "disassoc";
        case ATTACK_MODE_AUTHFLOOD: return "authflood";
        case ATTACK_MODE_MIXED:     return "mixed";
    }
    return "?";
}

int targets_mode_from_name(const char *name, attack_mode_t *out)
{
    if (!name || !out) return -1;
    if (strcasecmp(name, "broadcast") == 0) { *out = ATTACK_MODE_BROADCAST; return 0; }
    if (strcasecmp(name, "unicast")   == 0) { *out = ATTACK_MODE_UNICAST;   return 0; }
    if (strcasecmp(name, "disassoc")  == 0) { *out = ATTACK_MODE_DISASSOC;  return 0; }
    if (strcasecmp(name, "authflood") == 0) { *out = ATTACK_MODE_AUTHFLOOD; return 0; }
    if (strcasecmp(name, "mixed")     == 0) { *out = ATTACK_MODE_MIXED;     return 0; }
    return -1;
}
