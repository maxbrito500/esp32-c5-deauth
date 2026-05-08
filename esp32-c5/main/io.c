#include "io.h"

#include <stdio.h>
#include <string.h>

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

#define MAX_SINKS 4

typedef struct {
    io_sink_fn fn;
    void      *ctx;
} sink_t;

static sink_t s_sinks[MAX_SINKS];
static int    s_sink_count = 0;
static SemaphoreHandle_t s_mutex;

/* Hooked into esp_log so framework messages also go to the bus. */
static int log_vprintf(const char *fmt, va_list ap)
{
    char buf[256];
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    if (n < 0) return n;
    if (n >= (int)sizeof(buf)) n = sizeof(buf) - 1;

    xSemaphoreTake(s_mutex, portMAX_DELAY);
    for (int i = 0; i < s_sink_count; i++) {
        s_sinks[i].fn(buf, (size_t)n, s_sinks[i].ctx);
    }
    xSemaphoreGive(s_mutex);
    return n;
}

void io_init(void)
{
    s_mutex = xSemaphoreCreateMutex();
    s_sink_count = 0;
    esp_log_set_vprintf(log_vprintf);
}

int io_register_sink(io_sink_fn fn, void *ctx)
{
    xSemaphoreTake(s_mutex, portMAX_DELAY);
    int rc = -1;
    if (s_sink_count < MAX_SINKS) {
        s_sinks[s_sink_count].fn = fn;
        s_sinks[s_sink_count].ctx = ctx;
        s_sink_count++;
        rc = 0;
    }
    xSemaphoreGive(s_mutex);
    return rc;
}

void io_vlog(const char *fmt, va_list ap)
{
    char buf[256];
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    if (n < 0) return;
    if (n >= (int)sizeof(buf)) n = sizeof(buf) - 1;

    xSemaphoreTake(s_mutex, portMAX_DELAY);
    for (int i = 0; i < s_sink_count; i++) {
        s_sinks[i].fn(buf, (size_t)n, s_sinks[i].ctx);
    }
    xSemaphoreGive(s_mutex);
}

void io_log(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    io_vlog(fmt, ap);
    va_end(ap);
}
