#include "nvs_flash.h"
#include "esp_err.h"
#include "io.h"
#include "cli.h"
#include "transport_serial.h"
#include "transport_ble.h"
#include "wifi_ctrl.h"
#include "targets.h"
#include "acl.h"
#include "attack.h"

void app_main(void)
{
    esp_err_t nvs_err = nvs_flash_init();
    if (nvs_err == ESP_ERR_NVS_NO_FREE_PAGES || nvs_err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        nvs_flash_erase();
        nvs_flash_init();
    }
    io_init();
    targets_init();
    acl_init();
    attack_init();
    transport_serial_init();
    io_log("main: serial up\r\n");
    transport_ble_init();
    io_log("main: ble init done\r\n");
    wifi_ctrl_init();
    io_log("main: wifi up\r\n");
    cli_init();
}
