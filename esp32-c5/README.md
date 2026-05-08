# ESP32-C5 Dual-Band Deauther

Firmware for the Seeed Studio XIAO ESP32-C5. Educational / authorized
security testing only — use exclusively on networks you own or have
written permission to test.

## Quick start (VS Code)

Install the official `Espressif IDF` extension (id
`espressif.esp-idf-extension`) in VS Code, then open this folder.

The extension's status bar gives you:

- ESP-IDF: Build project — compiles
- ESP-IDF: Flash device — writes flash via the chip's built-in JTAG
- ESP-IDF: Monitor device — opens the serial console at 115200 baud

`.vscode/settings.json` points the extension at the C5 target and the
`board/esp32c5-builtin.cfg` OpenOCD config, so flashing goes over JTAG
and never touches the CDC console — no BOOT/RESET button presses
needed even when running firmware has the CDC channel busy.

The first time, also run the `Tasks: Run Task → Patch libnet80211.a`
step (or `cp patched_libnet/libnet80211.a $IDF_PATH/components/esp_wifi/lib/esp32c5/`)
so `esp_wifi_80211_tx` accepts spoofed-SA management frames. The
backup is saved as `libnet80211.a.orig`.

## Quick start (command line)

ESP-IDF v5.5.1+ on PATH (`source ~/esp/esp-idf/export.sh`).

```bash
./flash.sh                  # build + JTAG-flash + soft-reset over serial
./flash.sh --no-build       # flash only
./flash.sh --full           # also reflash bootloader + partition table
./serial.sh                 # interactive CLI (DTR/RTS held LOW)
```

`flash.sh` flashes via OpenOCD against `board/esp32c5-builtin.cfg`,
which uses the chip's built-in JTAG side of the USB-Serial-JTAG
controller. The CDC side stays free, so the running firmware's CLI is
not interrupted during flashing. After a successful flash, `flash.sh`
sends `reset` to the running firmware, which calls `esp_restart()`.

## Project layout

```
esp32-c5/
├── CMakeLists.txt              IDF top-level
├── partitions.csv              factory partition layout
├── sdkconfig.defaults          base IDF config (esp32c5, NimBLE, USB-CDC console)
├── patched_libnet/
│   └── libnet80211.a           drop-in replacement that enables spoofed-SA mgmt tx
├── flash.sh                    build + JTAG-flash + soft-reset
├── serial.sh                   interactive CLI (DTR=0 RTS=0)
├── tools/
│   └── serial_console.py       Python TTY client used by serial.sh
├── .vscode/
│   ├── settings.json           ESP-IDF extension config (target=esp32c5, JTAG flash)
│   ├── tasks.json              build / flash / monitor tasks
│   └── extensions.json         recommends espressif.esp-idf-extension
└── main/
    ├── CMakeLists.txt
    ├── main.c                  init order + boot status
    ├── io.{c,h}                log fanout to all transports
    ├── cli.{c,h}               command parser (transport-agnostic)
    ├── transport_serial.{c,h}  USB-Serial-JTAG TX/RX
    ├── transport_ble.{c,h}     NimBLE NUS GATT (currently disabled — see below)
    ├── frames.{c,h}            802.11 deauth / disassoc / auth-flood builders
    ├── wifi_ctrl.{c,h}         STA-mode init + dual-band scan
    ├── sniffer.{c,h}           promiscuous STA discovery
    ├── targets.{c,h}           AP / STA / selection state
    ├── acl.{c,h}               whitelist + blacklist (NVS-persisted)
    └── attack.{c,h}            attack scheduler
```

## CLI commands

```
help                          show help
scan                          dual-band wifi scan
ls                            list APs
sniff <ap_idx> <sec>          promiscuous capture for that AP — discovers STAs
stas                          list captured STAs
t24 <ap_idx>                  set 2.4 GHz target
t5  <ap_idx>                  set 5 GHz target
sta <sta_idx>                 set unicast STA target
clear                         clear selected targets
mode <broadcast|unicast|disassoc|authflood|mixed>
start <duration_sec>
stop                          stop attack early
status
wl add <mac> [bssid|sta]      whitelist add (never deauth) — persisted
wl rm  <mac> | wl ls | wl clear
bl add <mac> [bssid|sta]      blacklist add (always deauth) — persisted
bl rm  <mac> | bl ls | bl clear
reset                         soft-reset the chip (esp_restart)
```

### Whitelist / blacklist semantics

Whitelist is a hard veto — no frame is sent that targets a whitelisted
MAC, and no AP whose BSSID is whitelisted will be hit. If a whitelisted
STA is associated to the selected AP (per `sniff`), broadcast and
disassoc modes auto-downgrade to unicast against every non-whitelisted
STA.

Blacklist is an always-target overlay. Every attack cycle also fires
unicast deauths at any blacklisted STA visible in the sniff list, and
broadcast deauths at any blacklisted BSSID present in the AP scan list,
regardless of the currently selected `t24/t5/sta`. Whitelist always
beats blacklist for the same MAC.

## Why JTAG flash, not CDC

Stock IDF's flash flow uses esptool over the CDC ACM serial channel
with DTR/RTS-pulse-driven reset. On the XIAO C5, the USB-Serial-JTAG
controller's interpretation of CDC modem control lines is fragile —
pyserial's default `DTR=True` on open pulls BOOT low and traps the
chip in download mode across soft resets, which then cannot be
escaped without a physical EN-pin event. Flashing over JTAG bypasses
all of that: it goes through a separate USB endpoint and never
touches DTR/RTS or the CDC console.

## Why we don't use PlatformIO

Tried, doesn't work for this chip. The official `platformio/espressif32`
platform doesn't list `esp32c5` as a board. The
`Seeed-Studio/platform-seeedboards` package does ship a
`seeed-xiao-esp32-c5.json`, but its `espidf` framework builder
(`builder/frameworks/espidf.py`) imports two helper modules
(`component_manager.py`, `penv_setup.py`) that are referenced but
not present in the package, so the build fails before compilation
starts. Falling back to the official ESP-IDF VS Code extension is
the supported path.

## Status

- Serial CLI: working
- BLE GATT (NimBLE NUS): scaffolded but `nimble_port_init` hangs on this
  IDF + C5 combination — currently disabled in `main.c`. Investigation
  pending.
