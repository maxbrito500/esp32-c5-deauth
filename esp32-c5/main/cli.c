#include "cli.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"

#include "esp_system.h"

#include "io.h"
#include "wifi_ctrl.h"
#include "sniffer.h"
#include "targets.h"
#include "acl.h"
#include "attack.h"

#define CLI_LINE_MAX 256

static char s_line[CLI_LINE_MAX];
static size_t s_len = 0;
static SemaphoreHandle_t s_mutex;

static const char *HELP =
    "commands:\r\n"
    "  scan                            dual-band wifi scan\r\n"
    "  ls                              list APs\r\n"
    "  sniff <ap_idx> <sec>            promiscuous capture for that AP\r\n"
    "  stas                            list captured STAs\r\n"
    "  dev scan [sec]                  passive device sweep (default 13s)\r\n"
    "  dev ls                          list found devices\r\n"
    "  t24 <ap_idx>                    select 2.4 GHz target\r\n"
    "  t5  <ap_idx>                    select 5 GHz target\r\n"
    "  sta <sta_idx>                   select unicast STA target\r\n"
    "  clear                           clear selected targets\r\n"
    "  mode <broadcast|unicast|disassoc|authflood|mixed>\r\n"
    "  start <duration_sec>            start attack\r\n"
    "  stop                            stop attack\r\n"
    "  status                          show status\r\n"
    "  wl add <mac> [bssid|sta]        whitelist add (never deauth)\r\n"
    "  wl rm  <mac>                    whitelist remove\r\n"
    "  wl ls                           whitelist list\r\n"
    "  wl clear                        whitelist clear\r\n"
    "  bl add <mac> [bssid|sta]        blacklist add (always deauth)\r\n"
    "  bl rm  <mac>                    blacklist remove\r\n"
    "  bl ls                           blacklist list\r\n"
    "  bl clear                        blacklist clear\r\n"
    "  reset                           soft-reset the chip (esp_restart)\r\n"
    "  help                            this help\r\n";

#define MAX_TOK 8

static int tokenize(char *line, char *tok[MAX_TOK])
{
    int n = 0;
    char *p = line;
    while (*p && n < MAX_TOK) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;
        tok[n++] = p;
        while (*p && !isspace((unsigned char)*p)) p++;
        if (*p) *p++ = '\0';
    }
    return n;
}

static acl_kind_t parse_kind(const char *s)
{
    if (!s) return ACL_KIND_AUTO;
    if (strcasecmp(s, "bssid") == 0) return ACL_KIND_BSSID;
    if (strcasecmp(s, "sta")   == 0) return ACL_KIND_STA;
    return ACL_KIND_AUTO;
}

static void cmd_acl(int argc, char *argv[], bool whitelist)
{
    if (argc < 2) { io_log("usage: %s <add|rm|ls|clear> ...\r\n", argv[0]); return; }
    const char *sub = argv[1];

    if (strcasecmp(sub, "ls") == 0) {
        if (whitelist) acl_wl_list(); else acl_bl_list();
        return;
    }
    if (strcasecmp(sub, "clear") == 0) {
        if (whitelist) acl_wl_clear(); else acl_bl_clear();
        io_log("%s: cleared\r\n", argv[0]);
        return;
    }
    if (strcasecmp(sub, "add") == 0) {
        if (argc < 3) { io_log("usage: %s add <mac> [bssid|sta]\r\n", argv[0]); return; }
        uint8_t mac[6];
        if (acl_parse_mac(argv[2], mac) != 0) { io_log("%s: bad mac\r\n", argv[0]); return; }
        acl_kind_t k = (argc >= 4) ? parse_kind(argv[3]) : ACL_KIND_AUTO;
        int rc = whitelist ? acl_wl_add(mac, k) : acl_bl_add(mac, k);
        if      (rc == 0)  io_log("%s: added\r\n", argv[0]);
        else if (rc == -1) io_log("%s: list full\r\n", argv[0]);
        else if (rc == -2) io_log("%s: already present\r\n", argv[0]);
        return;
    }
    if (strcasecmp(sub, "rm") == 0) {
        if (argc < 3) { io_log("usage: %s rm <mac>\r\n", argv[0]); return; }
        uint8_t mac[6];
        if (acl_parse_mac(argv[2], mac) != 0) { io_log("%s: bad mac\r\n", argv[0]); return; }
        int rc = whitelist ? acl_wl_remove(mac) : acl_bl_remove(mac);
        io_log("%s: %s\r\n", argv[0], (rc == 0) ? "removed" : "not found");
        return;
    }
    io_log("%s: unknown subcommand `%s`\r\n", argv[0], sub);
}

static void run_line(char *line)
{
    char *argv[MAX_TOK];
    int argc = tokenize(line, argv);
    if (argc == 0) return;

    const char *cmd = argv[0];

    if (strcasecmp(cmd, "help") == 0 || strcmp(cmd, "?") == 0) {
        io_log("%s", HELP);
        return;
    }
    if (strcasecmp(cmd, "scan") == 0) {
        wifi_ctrl_scan();
        return;
    }
    if (strcasecmp(cmd, "ls") == 0) {
        targets_list_aps();
        return;
    }
    if (strcasecmp(cmd, "stas") == 0) {
        targets_list_stas();
        return;
    }
    if (strcasecmp(cmd, "sniff") == 0) {
        if (argc < 3) { io_log("usage: sniff <ap_idx> <sec>\r\n"); return; }
        int idx = atoi(argv[1]);
        int sec = atoi(argv[2]);
        target_ap_t ap;
        if (targets_get_ap((uint16_t)idx, &ap) != 0) { io_log("sniff: bad ap_idx\r\n"); return; }
        sniffer_run(ap.channel, ap.bssid, (uint32_t)sec);
        return;
    }
    if (strcasecmp(cmd, "t24") == 0) {
        if (argc < 2) { io_log("usage: t24 <ap_idx>\r\n"); return; }
        int idx = atoi(argv[1]);
        int rc = targets_select_24((uint16_t)idx);
        if      (rc == 0)  io_log("t24: ok\r\n");
        else if (rc == -1) io_log("t24: that AP is 5 GHz, not 2.4\r\n");
        else               io_log("t24: bad index\r\n");
        return;
    }
    if (strcasecmp(cmd, "t5") == 0) {
        if (argc < 2) { io_log("usage: t5 <ap_idx>\r\n"); return; }
        int idx = atoi(argv[1]);
        int rc = targets_select_5((uint16_t)idx);
        if      (rc == 0)  io_log("t5: ok\r\n");
        else if (rc == -1) io_log("t5: that AP is 2.4 GHz, not 5\r\n");
        else               io_log("t5: bad index\r\n");
        return;
    }
    if (strcasecmp(cmd, "sta") == 0) {
        if (argc < 2) { io_log("usage: sta <sta_idx>\r\n"); return; }
        int idx = atoi(argv[1]);
        int rc = targets_select_sta((uint16_t)idx);
        io_log("sta: %s\r\n", (rc == 0) ? "ok" : "bad index");
        return;
    }
    if (strcasecmp(cmd, "clear") == 0) {
        targets_clear_selection();
        targets_sel_clear();
        io_log("clear: selection reset\r\n");
        return;
    }
    if (strcasecmp(cmd, "sel") == 0) {
        if (argc < 2 || strcasecmp(argv[1], "ls") == 0) {
            targets_list_sel();
            return;
        }
        if (strcasecmp(argv[1], "clear") == 0) {
            targets_sel_clear();
            io_log("sel: cleared\r\n");
            return;
        }
        int idx = atoi(argv[1]);
        if (idx < 0 || idx >= targets_ap_count()) {
            io_log("sel: bad index\r\n");
            return;
        }
        targets_sel_toggle((uint16_t)idx);
        io_log("sel: %d %s\r\n", idx,
               targets_sel_contains((uint16_t)idx) ? "on" : "off");
        return;
    }
    if (strcasecmp(cmd, "mode") == 0) {
        if (argc < 2) {
            io_log("mode: %s\r\n", targets_mode_name(targets_get_mode()));
            return;
        }
        attack_mode_t m;
        if (targets_mode_from_name(argv[1], &m) != 0) {
            io_log("mode: unknown (broadcast|unicast|disassoc|authflood|mixed)\r\n");
            return;
        }
        targets_set_mode(m);
        io_log("mode: %s\r\n", targets_mode_name(m));
        return;
    }
    if (strcasecmp(cmd, "start") == 0) {
        /* duration is optional; 0 or omitted means run until stop */
        uint32_t d = (argc >= 2) ? (uint32_t)atoi(argv[1]) : 0;
        attack_start(d);
        return;
    }
    if (strcasecmp(cmd, "nuke") == 0) {
        uint32_t d = (argc >= 2) ? (uint32_t)atoi(argv[1]) : 30;
        attack_nuke_start(d);
        return;
    }
    if (strcasecmp(cmd, "stop") == 0) {
        attack_stop();
        return;
    }
    if (strcasecmp(cmd, "status") == 0) {
        attack_print_status();
        return;
    }
    if (strcasecmp(cmd, "wl") == 0) { cmd_acl(argc, argv, true);  return; }
    if (strcasecmp(cmd, "bl") == 0) { cmd_acl(argc, argv, false); return; }

    if (strcasecmp(cmd, "dev") == 0) {
        if (argc < 2) { io_log("usage: dev scan [sec] | dev ls\r\n"); return; }
        if (strcasecmp(argv[1], "ls") == 0) {
            targets_list_stas_machine();
        } else if (strcasecmp(argv[1], "scan") == 0) {
            uint32_t sec = (argc >= 3) ? (uint32_t)atoi(argv[2]) : 13;
            targets_clear_stas();
            sniffer_sweep(sec);
            targets_list_stas_machine();
        } else {
            io_log("usage: dev scan [sec] | dev ls\r\n");
        }
        return;
    }

    if (strcasecmp(cmd, "reset") == 0 || strcasecmp(cmd, "reboot") == 0) {
        io_log("reset: restarting chip in 200ms\r\n");
        /* Give the I/O bus time to drain before the chip restarts. */
        vTaskDelay(pdMS_TO_TICKS(200));
        esp_restart();
        return;  /* unreachable */
    }

    io_log("unknown: %s (try `help`)\r\n", cmd);
}

void cli_init(void)
{
    s_mutex = xSemaphoreCreateMutex();
    s_len = 0;
}

void cli_feed(const char *bytes, size_t len)
{
    xSemaphoreTake(s_mutex, portMAX_DELAY);
    for (size_t i = 0; i < len; i++) {
        char c = bytes[i];
        if (c == '\r') continue;
        if (c == '\n') {
            s_line[s_len] = '\0';
            char copy[CLI_LINE_MAX];
            memcpy(copy, s_line, s_len + 1);
            s_len = 0;
            xSemaphoreGive(s_mutex);
            run_line(copy);
            xSemaphoreTake(s_mutex, portMAX_DELAY);
            continue;
        }
        if (c == 0x08 || c == 0x7f) {  /* backspace / DEL */
            if (s_len > 0) s_len--;
            continue;
        }
        if (s_len < CLI_LINE_MAX - 1) {
            s_line[s_len++] = c;
        } else {
            /* line too long — drop */
            s_len = 0;
        }
    }
    xSemaphoreGive(s_mutex);
}
