# Seeed Studio XIAO ESP32-C5 — Specs

Reference board for this project.

- Wiki / getting started: https://wiki.seeedstudio.com/xiao_esp32c5_getting_started/
- Official OSHW repo (schematics, KiCad, datasheets): https://github.com/Seeed-Studio/OSHW-XIAO-Series
- PlatformIO board definition: https://github.com/Seeed-Studio/platform-seeedboards/blob/main/boards/seeed-xiao-esp32-c5.json

## Chip & Performance

| Item | Value |
|---|---|
| MCU | ESP32-C5 |
| Core | RISC-V 32-bit, single-core |
| Clock | up to 240 MHz |
| On-chip SRAM | 384 KB |
| ROM | 320 KB |
| PSRAM (on module) | 8 MB |
| Flash (on module) | 8 MB |

## Wireless

- **Wi-Fi 6** (802.11 a/b/g/n/ac/ax), **dual-band 2.4 GHz + 5 GHz** — first XIAO board with 5 GHz support.
- **Bluetooth 5 (LE)** with mesh.
- External RF antenna (IPEX/U.FL) included; antenna must be attached before powering on.

## Physical

| Item | Value |
|---|---|
| Dimensions | 21 × 17.8 mm |
| USB | Type-C |
| Buttons | Reset, Boot |
| Form factor | XIAO (14-pin, single-sided components) |

## Power

- Input: USB-C 5 V (VBUS) **or** 3.7 V Li-ion battery via dedicated pads.
- Onboard 3.3 V regulator; 3V3 pin available on header.
- Battery charge IC: **SGM40567**.
- Battery voltage rail switch: **TPS22916CYFPR** (enable via GPIO26, read via GPIO6).
- Charge status LED (red): tied to VCC_3V3.

## Onboard indicators

| Component | Pin / Net |
|---|---|
| User LED (yellow, `LED_BUILTIN`) | GPIO27 |
| Charge LED (red) | VCC_3V3 |
| Boot button | GPIO28 |
| Reset button | EN |

## Pinout (14-pin header)

| Header | Function | GPIO | Notes |
|---|---|---|---|
| D0 | GPIO / ADC | GPIO1 | analog input |
| D1 | GPIO / ADC | — | ADC capable |
| D2 | GPIO / ADC | — | ADC capable |
| D3 | GPIO / ADC | — | ADC capable |
| D4 | I2C SDA | GPIO23 | default I2C |
| D5 | I2C SCL | GPIO24 | default I2C |
| D6 | UART TX | GPIO11 | default UART0 |
| D7 | UART RX | GPIO12 | default UART0 |
| D8 | SPI SCK | GPIO8 | default SPI |
| D9 | SPI MISO | GPIO9 | default SPI |
| D10 | SPI MOSI | GPIO10 | default SPI |
| 5V | VBUS | — | USB 5 V in/out |
| GND | Ground | — | |
| 3V3 | 3.3 V rail | — | regulated output |

### Capability summary

- **GPIO:** up to 11 user-accessible, all PWM-capable.
- **ADC:** 5 channels.
- **I2C:** 1 (D4/D5).
- **SPI:** 1 (D8/D9/D10).
- **UART:** 2 (D6/D7 default; second UART remappable).
- **JTAG:** pads on the back side (MTMS, MTDI, MTCK, MTDO).
- **USB:** USB 2.0 Full-Speed CDC/JTAG via Type-C.

## Security

- AES-128/256, SHA family, HMAC hardware accelerators.
- Secure Boot v2.
- Flash encryption.

## Toolchain notes

- Arduino: install Seeed `xiao-esp32` board package; select **XIAO_ESP32C5**.
- ESP-IDF: target `esp32c5` (requires ESP-IDF release with C5 support).
- PlatformIO: board id `seeed-xiao-esp32-c5` from the seeedboards platform.
