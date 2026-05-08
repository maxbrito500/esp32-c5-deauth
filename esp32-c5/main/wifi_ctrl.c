#include "wifi_ctrl.h"

#include <stdlib.h>
#include <string.h>

#include "esp_event.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "esp_log.h"

#include "io.h"
#include "targets.h"

static const char *TAG = "wifi";

void wifi_ctrl_init(void)
{
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_start());

    ESP_LOGI(TAG, "wifi: STA mode up");
}

int wifi_ctrl_scan(void)
{
    wifi_scan_config_t cfg = {
        .ssid = NULL,
        .bssid = NULL,
        .channel = 0,           /* all channels, both bands */
        .show_hidden = true,
        .scan_type = WIFI_SCAN_TYPE_ACTIVE,
        .scan_time.active = { .min = 80, .max = 120 },
    };

    io_log("scan: start (dual-band)\r\n");
    esp_err_t err = esp_wifi_scan_start(&cfg, true);
    if (err != ESP_OK) {
        io_log("scan: failed (err=%d)\r\n", err);
        return -1;
    }

    uint16_t n = 0;
    esp_wifi_scan_get_ap_num(&n);
    if (n == 0) {
        targets_set_aps(NULL, 0);
        io_log("scan: no APs found\r\n");
        return 0;
    }
    if (n > WIFI_SCAN_MAX_APS) n = WIFI_SCAN_MAX_APS;

    wifi_ap_record_t *recs = calloc(n, sizeof(wifi_ap_record_t));
    if (!recs) {
        io_log("scan: oom\r\n");
        return -1;
    }
    esp_wifi_scan_get_ap_records(&n, recs);

    target_ap_t *aps = calloc(n, sizeof(target_ap_t));
    if (!aps) {
        free(recs);
        return -1;
    }
    for (uint16_t i = 0; i < n; i++) {
        memcpy(aps[i].bssid, recs[i].bssid, 6);
        strncpy(aps[i].ssid, (const char *)recs[i].ssid, sizeof(aps[i].ssid) - 1);
        aps[i].ssid[sizeof(aps[i].ssid) - 1] = '\0';
        aps[i].channel = recs[i].primary;
        aps[i].rssi = recs[i].rssi;
        aps[i].band_5ghz = (recs[i].primary > 14);
    }
    targets_set_aps(aps, n);

    free(recs);
    free(aps);

    io_log("scan: %u APs\r\n", (unsigned)n);
    return n;
}

void wifi_ctrl_set_channel(uint8_t channel)
{
    esp_wifi_set_channel(channel, WIFI_SECOND_CHAN_NONE);
}
