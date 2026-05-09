/* Stub when CONFIG_BT_ENABLED=n. Full implementation in git. */
#include "sdkconfig.h"
#include "transport_ble.h"

#ifndef CONFIG_BT_ENABLED
void transport_ble_init(void) {}
#else
/* Full implementation below */
#include <stdint.h>
#include <stddef.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/stream_buffer.h"

#include "esp_log.h"
#include "esp_timer.h"

#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#include "io.h"
#include "cli.h"

static const char *TAG = "ble";

static const ble_uuid128_t NUS_SVC_UUID = BLE_UUID128_INIT(
    0x9E, 0xCA, 0xDC, 0x24, 0x0E, 0xE5, 0xA9, 0xE0,
    0x93, 0xF3, 0xA3, 0xB5, 0x01, 0x00, 0x40, 0x6E);
static const ble_uuid128_t NUS_RX_UUID = BLE_UUID128_INIT(
    0x9E, 0xCA, 0xDC, 0x24, 0x0E, 0xE5, 0xA9, 0xE0,
    0x93, 0xF3, 0xA3, 0xB5, 0x02, 0x00, 0x40, 0x6E);
static const ble_uuid128_t NUS_TX_UUID = BLE_UUID128_INIT(
    0x9E, 0xCA, 0xDC, 0x24, 0x0E, 0xE5, 0xA9, 0xE0,
    0x93, 0xF3, 0xA3, 0xB5, 0x03, 0x00, 0x40, 0x6E);

#define BLE_MTU            247
#define MAX_NOTIFY_PAYLOAD (BLE_MTU - 3)
#define TX_BUF_BYTES       4096
#define BLE_MAX_CONN       3
#define IDLE_TIMEOUT_SEC   60   /* force-disconnect after 60s silence */
#define IDLE_CHECK_MS      10000

static uint16_t          s_conn_handles[BLE_MAX_CONN];
static volatile bool     s_notify_enabled[BLE_MAX_CONN];
static uint32_t          s_last_rx_sec[BLE_MAX_CONN];
static uint16_t          s_tx_attr_handle = 0;
static uint8_t           s_own_addr_type;
static StreamBufferHandle_t s_tx_sb;
static struct ble_npl_callout s_adv_callout;
static struct ble_npl_callout s_idle_callout;

static int gap_event_cb(struct ble_gap_event *event, void *arg);
static void start_advertising(void);

static uint32_t now_sec(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000000ULL);
}

static int rx_access_cb(uint16_t conn_handle, uint16_t attr_handle,
                        struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)attr_handle; (void)arg;
    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) return BLE_ATT_ERR_UNLIKELY;
    uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
    if (len == 0) return 0;
    char buf[256];
    if (len > sizeof(buf)) len = sizeof(buf);
    if (ble_hs_mbuf_to_flat(ctxt->om, buf, len, NULL) != 0)
        return BLE_ATT_ERR_UNLIKELY;

    /* Reset idle watchdog for this connection. */
    for (int i = 0; i < BLE_MAX_CONN; i++) {
        if (s_conn_handles[i] == conn_handle) {
            s_last_rx_sec[i] = now_sec();
            break;
        }
    }

    cli_feed(buf, len);
    bool has_nl = false;
    for (uint16_t i = 0; i < len; i++) if (buf[i] == '\n') { has_nl = true; break; }
    if (!has_nl) cli_feed("\n", 1);
    return 0;
}

static int tx_access_cb(uint16_t conn_handle, uint16_t attr_handle,
                        struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle; (void)attr_handle; (void)ctxt; (void)arg;
    return 0;
}

static const struct ble_gatt_chr_def s_chrs[] = {
    { .uuid = &NUS_RX_UUID.u, .access_cb = rx_access_cb,
      .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP },
    { .uuid = &NUS_TX_UUID.u, .access_cb = tx_access_cb,
      .val_handle = &s_tx_attr_handle,
      .flags = BLE_GATT_CHR_F_NOTIFY | BLE_GATT_CHR_F_READ },
    { 0 }
};

static const struct ble_gatt_svc_def s_svcs[] = {
    { .type = BLE_GATT_SVC_TYPE_PRIMARY, .uuid = &NUS_SVC_UUID.u,
      .characteristics = s_chrs },
    { 0 }
};

static void adv_callout_fn(struct ble_npl_event *ev)
{
    (void)ev;
    start_advertising();
}

/* Runs on the NimBLE event queue every IDLE_CHECK_MS.
 * Safe to call ble_gap_terminate from here. */
static void idle_check_fn(struct ble_npl_event *ev)
{
    (void)ev;
    uint32_t now = now_sec();
    for (int i = 0; i < BLE_MAX_CONN; i++) {
        if (s_conn_handles[i] == BLE_HS_CONN_HANDLE_NONE) continue;
        if (now - s_last_rx_sec[i] > IDLE_TIMEOUT_SEC) {
            ESP_LOGW(TAG, "slot %d idle >%ds, disconnecting h=%u",
                     i, IDLE_TIMEOUT_SEC, s_conn_handles[i]);
            io_log("ble: slot %d idle timeout — disconnecting\r\n", i);
            ble_gap_terminate(s_conn_handles[i], 0x13 /* remote user */);
        }
    }
    ble_npl_callout_reset(&s_idle_callout,
                          ble_npl_time_ms_to_ticks32(IDLE_CHECK_MS));
}

static void start_advertising(void)
{
    struct ble_hs_adv_fields fields = {0};
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    const char *name = ble_svc_gap_device_name();
    fields.name = (uint8_t *)name;
    fields.name_len = strlen(name);
    fields.name_is_complete = 1;
    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) { ESP_LOGW(TAG, "adv_set_fields rc=%d", rc); return; }

    /* Put the 128-bit NUS UUID in the scan response to stay within the
     * 31-byte advertisement limit (flags 3B + name 18B = 21B). */
    struct ble_hs_adv_fields rsp = {0};
    rsp.uuids128 = (ble_uuid128_t *)&NUS_SVC_UUID;
    rsp.num_uuids128 = 1;
    rsp.uuids128_is_complete = 1;
    rc = ble_gap_adv_rsp_set_fields(&rsp);
    if (rc != 0) ESP_LOGW(TAG, "adv_rsp_set_fields rc=%d", rc);

    struct ble_gap_adv_params adv = {0};
    adv.conn_mode = BLE_GAP_CONN_MODE_UND;
    adv.disc_mode = BLE_GAP_DISC_MODE_GEN;
    adv.itvl_min  = BLE_GAP_ADV_FAST_INTERVAL1_MIN;
    adv.itvl_max  = BLE_GAP_ADV_FAST_INTERVAL1_MAX;
    rc = ble_gap_adv_start(s_own_addr_type, NULL, BLE_HS_FOREVER, &adv, gap_event_cb, NULL);
    if (rc == 0 || rc == BLE_HS_EALREADY) {
        ESP_LOGI(TAG, "advertising as ESP32C5-Deauther");
    } else {
        /* Stack not ready yet (e.g. BLE_HS_EBUSY right after disconnect).
         * Retry from the host event queue after 200 ms. */
        ESP_LOGW(TAG, "adv_start rc=%d, retry in 200 ms", rc);
        ble_npl_callout_reset(&s_adv_callout,
                              ble_npl_time_ms_to_ticks32(200));
    }
}

static int gap_event_cb(struct ble_gap_event *event, void *arg)
{
    (void)arg;
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0) {
            uint16_t h = event->connect.conn_handle;
            int slot = -1;
            for (int i = 0; i < BLE_MAX_CONN; i++) {
                if (s_conn_handles[i] == BLE_HS_CONN_HANDLE_NONE) { slot = i; break; }
            }
            if (slot < 0) {
                /* All slots full — refuse the connection. */
                ESP_LOGW(TAG, "max connections reached, refusing h=%u", h);
                ble_gap_terminate(h, BLE_ERR_CONN_LIMIT);
            } else {
                s_conn_handles[slot] = h;
                s_last_rx_sec[slot]  = now_sec();
                ESP_LOGI(TAG, "connected slot=%d h=%u", slot, h);
                /* Keep advertising so another peer can still connect. */
                start_advertising();
            }
        } else {
            start_advertising();
        }
        return 0;

    case BLE_GAP_EVENT_DISCONNECT: {
        uint16_t h = event->disconnect.conn.conn_handle;
        for (int i = 0; i < BLE_MAX_CONN; i++) {
            if (s_conn_handles[i] == h) {
                s_conn_handles[i]    = BLE_HS_CONN_HANDLE_NONE;
                s_notify_enabled[i]  = false;
                s_last_rx_sec[i]     = 0;
                ESP_LOGI(TAG, "disconnected slot=%d h=%u", i, h);
                break;
            }
        }
        start_advertising();
        return 0;
    }

    case BLE_GAP_EVENT_ADV_COMPLETE: start_advertising(); return 0;

    case BLE_GAP_EVENT_SUBSCRIBE:
        if (event->subscribe.attr_handle == s_tx_attr_handle) {
            uint16_t h = event->subscribe.conn_handle;
            for (int i = 0; i < BLE_MAX_CONN; i++) {
                if (s_conn_handles[i] == h) {
                    s_notify_enabled[i] = event->subscribe.cur_notify;
                    ESP_LOGI(TAG, "notify slot=%d %s", i,
                             s_notify_enabled[i] ? "on" : "off");
                    break;
                }
            }
        }
        return 0;

    case BLE_GAP_EVENT_MTU:
        ESP_LOGI(TAG, "mtu=%u", event->mtu.value); return 0;
    }
    return 0;
}

static void on_sync(void)
{
    int rc = ble_hs_id_infer_auto(0, &s_own_addr_type);
    if (rc != 0) { ESP_LOGE(TAG, "addr_infer rc=%d", rc); return; }
    for (int i = 0; i < BLE_MAX_CONN; i++) {
        s_conn_handles[i]   = BLE_HS_CONN_HANDLE_NONE;
        s_notify_enabled[i] = false;
        s_last_rx_sec[i]    = 0;
    }
    /* Start the periodic idle watchdog. */
    ble_npl_callout_reset(&s_idle_callout,
                          ble_npl_time_ms_to_ticks32(IDLE_CHECK_MS));
    start_advertising();
}

static void on_reset(int reason)
{
    ESP_LOGW(TAG, "reset: %d — restarting advertising in 500 ms", reason);
    for (int i = 0; i < BLE_MAX_CONN; i++) {
        s_conn_handles[i]   = BLE_HS_CONN_HANDLE_NONE;
        s_notify_enabled[i] = false;
        s_last_rx_sec[i]    = 0;
    }
    ble_npl_callout_reset(&s_adv_callout, ble_npl_time_ms_to_ticks32(500));
}

static void host_task(void *arg)
{
    (void)arg;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

static void tx_task(void *arg)
{
    (void)arg;
    uint8_t buf[MAX_NOTIFY_PAYLOAD];
    for (;;) {
        size_t n = xStreamBufferReceive(s_tx_sb, buf, sizeof(buf), portMAX_DELAY);
        if (n == 0) continue;
        for (int i = 0; i < BLE_MAX_CONN; i++) {
            if (s_conn_handles[i] == BLE_HS_CONN_HANDLE_NONE) continue;
            if (!s_notify_enabled[i]) continue;
            /* ble_gatts_notify_custom takes ownership of the mbuf — allocate
             * a fresh one for each connected peer. */
            struct os_mbuf *om = ble_hs_mbuf_from_flat(buf, n);
            if (!om) continue;
            ble_gatts_notify_custom(s_conn_handles[i], s_tx_attr_handle, om);
        }
    }
}

static void ble_sink(const char *buf, size_t len, void *ctx)
{
    (void)ctx;
    /* Quick check: any subscriber? */
    bool any = false;
    for (int i = 0; i < BLE_MAX_CONN; i++) {
        if (s_notify_enabled[i]) { any = true; break; }
    }
    if (!any) return;
    xStreamBufferSend(s_tx_sb, buf, len, 0);
}

void transport_ble_init(void)
{
    io_log("ble: init\r\n");

    for (int i = 0; i < BLE_MAX_CONN; i++) {
        s_conn_handles[i]   = BLE_HS_CONN_HANDLE_NONE;
        s_notify_enabled[i] = false;
        s_last_rx_sec[i]    = 0;
    }

    s_tx_sb = xStreamBufferCreate(TX_BUF_BYTES, 1);
    if (!s_tx_sb) { io_log("ble: stream buffer alloc failed\r\n"); return; }

    int rc = nimble_port_init();
    io_log("ble: nimble_port_init rc=%d\r\n", rc);
    if (rc != 0) return;

    ble_npl_callout_init(&s_adv_callout, nimble_port_get_dflt_eventq(),
                         adv_callout_fn, NULL);
    ble_npl_callout_init(&s_idle_callout, nimble_port_get_dflt_eventq(),
                         idle_check_fn, NULL);

    ble_hs_cfg.sync_cb  = on_sync;
    ble_hs_cfg.reset_cb = on_reset;

    ble_svc_gap_init();
    ble_svc_gatt_init();

    rc = ble_gatts_count_cfg(s_svcs);
    io_log("ble: count_cfg rc=%d\r\n", rc);
    if (rc != 0) return;

    rc = ble_gatts_add_svcs(s_svcs);
    io_log("ble: add_svcs rc=%d\r\n", rc);
    if (rc != 0) return;

    ble_svc_gap_device_name_set("ESP32C5-Deauther");
    ble_att_set_preferred_mtu(BLE_MTU);

    nimble_port_freertos_init(host_task);
    xTaskCreate(tx_task, "ble_tx", 4096, NULL, 4, NULL);
    io_register_sink(ble_sink, NULL);
    io_log("ble: host task started, waiting for sync\r\n");
}
#endif /* CONFIG_BT_ENABLED */
