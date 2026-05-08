#include "transport_serial.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/stream_buffer.h"

#include "hal/usb_serial_jtag_ll.h"

#include "io.h"
#include "cli.h"

/* Direct hardware-FIFO transport with non-blocking sink.
 *
 * The original design called fifo_write() directly from serial_sink(), which
 * blocks (via vTaskDelay) when the USB TX FIFO is full (i.e. no host reading).
 * serial_sink() is called while the io mutex is held, so any other task that
 * tried to log during that window — including the NimBLE host task — would
 * deadlock waiting for the mutex. This prevented BLE from ever syncing.
 *
 * Fix: mirror the BLE transport pattern. serial_sink() puts data into a
 * stream buffer (non-blocking, drops if full). A dedicated tx_task drains
 * the stream buffer to the USB FIFO — blocking is fine there since it runs
 * in its own task context without holding any shared lock.
 */

#define TX_BUF_BYTES 4096

static StreamBufferHandle_t s_tx_sb;

static void fifo_write(const uint8_t *buf, size_t len)
{
    size_t i = 0;
    while (i < len) {
        if (usb_serial_jtag_ll_txfifo_writable()) {
            int n = usb_serial_jtag_ll_write_txfifo(buf + i, len - i);
            if (n > 0) i += n;
            usb_serial_jtag_ll_txfifo_flush();
        } else {
            vTaskDelay(1);
        }
    }
}

static void serial_sink(const char *buf, size_t len, void *ctx)
{
    (void)ctx;
    if (!buf || !len) return;
    xStreamBufferSend(s_tx_sb, buf, len, 0);  /* non-blocking: drops if full */
}

static void tx_task(void *arg)
{
    (void)arg;
    uint8_t buf[256];
    for (;;) {
        size_t n = xStreamBufferReceive(s_tx_sb, buf, sizeof(buf), portMAX_DELAY);
        if (n > 0) fifo_write(buf, n);
    }
}

static void rx_task(void *arg)
{
    (void)arg;
    uint8_t buf[64];
    for (;;) {
        int n = usb_serial_jtag_ll_read_rxfifo(buf, sizeof(buf));
        if (n > 0) {
            cli_feed((const char *)buf, (size_t)n);
        } else {
            vTaskDelay(pdMS_TO_TICKS(10));
        }
    }
}

void transport_serial_init(void)
{
    s_tx_sb = xStreamBufferCreate(TX_BUF_BYTES, 1);
    io_register_sink(serial_sink, NULL);
    xTaskCreate(tx_task, "ser_tx", 2048, NULL, 8, NULL);
    xTaskCreate(rx_task, "ser_rx", 4096, NULL, 8, NULL);
}
