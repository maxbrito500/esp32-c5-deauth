#pragma once

#include <stdint.h>
#include <stdbool.h>

#define TARGETS_MAX_APS  64
#define TARGETS_MAX_STAS 64
#define TARGETS_SSID_LEN 33

typedef struct {
    uint8_t  bssid[6];
    char     ssid[TARGETS_SSID_LEN];
    uint8_t  channel;
    int8_t   rssi;
    bool     band_5ghz;
} target_ap_t;

typedef struct {
    uint8_t  mac[6];
    uint8_t  bssid[6];   /* AP it's associated with (best guess) */
    uint8_t  channel;
    int8_t   rssi;
} target_sta_t;

typedef enum {
    ATTACK_MODE_BROADCAST = 0,  /* deauth FF:FF:FF:FF:FF:FF on each target AP */
    ATTACK_MODE_UNICAST,        /* deauth the selected STA */
    ATTACK_MODE_DISASSOC,       /* same as broadcast but disassoc subtype */
    ATTACK_MODE_AUTHFLOOD,      /* auth-flood the target AP */
    ATTACK_MODE_MIXED,          /* rotate through all */
} attack_mode_t;

void targets_init(void);

/* AP list (mutex-protected). */
void   targets_set_aps(const target_ap_t *aps, uint16_t n);
int    targets_get_ap(uint16_t idx, target_ap_t *out);
int    targets_ap_count(void);
void   targets_list_aps(void);  /* prints to io_log */

/* STA list (populated by sniffer). */
void   targets_clear_stas(void);
bool   targets_add_sta(const uint8_t *mac, const uint8_t *bssid, uint8_t channel, int8_t rssi);
int    targets_get_sta(uint16_t idx, target_sta_t *out);
int    targets_sta_count(void);
void   targets_list_stas(void);

/* Multi-AP selection list (replaces the single t24/t5 slots). */
#define TARGETS_MAX_SEL 16
void targets_sel_toggle(uint16_t idx);       /* add or remove from list */
void targets_sel_clear(void);
bool targets_sel_contains(uint16_t idx);
int  targets_sel_count(void);
int  targets_get_sel_ap(int n, target_ap_t *out); /* nth selected AP */
void targets_list_sel(void);                 /* prints "sel: i j k\r\n" */

/* Legacy single-target API (kept for backwards compat with sniff/sta). */
int  targets_select_24(uint16_t ap_idx);
int  targets_select_5(uint16_t ap_idx);
int  targets_select_sta(uint16_t sta_idx);
void targets_clear_selection(void);

bool targets_get_selected_24(target_ap_t *out);
bool targets_get_selected_5(target_ap_t *out);
bool targets_get_selected_sta(target_sta_t *out);

void targets_set_mode(attack_mode_t m);
attack_mode_t targets_get_mode(void);
const char *targets_mode_name(attack_mode_t m);
int  targets_mode_from_name(const char *name, attack_mode_t *out);
