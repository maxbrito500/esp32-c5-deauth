#!/usr/bin/env bash
# One-step build + flash + reset for the XIAO ESP32-C5.
#
# Flash via JTAG (OpenOCD) to write the bins, then esptool --after hard_reset
# to boot the app. The JTAG CPU reset (cause 24) parks the ROM in download
# mode; esptool connects with --before default_reset (USBJTAGSerialReset) and
# the hard_reset command exits download mode and boots from flash.

set -euo pipefail

PORT="${PORT:-/dev/ttyACM0}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BIN="$PROJECT_DIR/build/esp32c5_deauther.bin"
BL_BIN="$PROJECT_DIR/build/bootloader/bootloader.bin"
PT_BIN="$PROJECT_DIR/build/partition_table/partition-table.bin"

OOCD_HOME="$HOME/.espressif/tools/openocd-esp32/v0.12.0-esp32-20250707/openocd-esp32"
OOCD_BIN="$OOCD_HOME/bin/openocd"
OOCD_SCRIPTS="$OOCD_HOME/share/openocd/scripts"

DO_BUILD=1
DO_FLASH=1
DO_RESET=1
FLASH_BL=0

usage() {
    cat <<EOF
Usage: $0 [options]
  --no-build       skip idf.py build
  --no-flash       skip flash
  --no-reset       skip the post-flash serial reset
  --full           also reflash bootloader + partition table (default: app only)
  -p, --port PATH  serial port (default: \$PORT or /dev/ttyACM0)
  -h, --help       this help
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build) DO_BUILD=0; shift ;;
        --no-flash) DO_FLASH=0; shift ;;
        --no-reset) DO_RESET=0; shift ;;
        --full)     FLASH_BL=1; shift ;;
        -p|--port)  PORT="$2"; shift 2 ;;
        -h|--help)  usage ;;
        *)          echo "unknown arg: $1"; usage ;;
    esac
done

if [[ -z "${IDF_PATH:-}" ]]; then
    if [[ -f "$HOME/esp/esp-idf/export.sh" ]]; then
        # shellcheck disable=SC1091
        source "$HOME/esp/esp-idf/export.sh" >/dev/null
    else
        echo "IDF_PATH unset and ~/esp/esp-idf/export.sh not found." >&2
        exit 1
    fi
fi

if [[ "$DO_BUILD" == 1 ]]; then
    cd "$PROJECT_DIR"
    idf.py build
fi

if [[ "$DO_FLASH" == 1 ]]; then
    fuser -k "$PORT" >/dev/null 2>&1 || true
    sleep 0.3

    # 1. JTAG: write the bins.
    OOCD_CMDS=()
    if [[ "$FLASH_BL" == 1 ]]; then
        OOCD_CMDS+=("-c" "program_esp $BL_BIN 0x2000 verify")
        OOCD_CMDS+=("-c" "program_esp $PT_BIN 0x8000 verify")
    fi
    OOCD_CMDS+=("-c" "program_esp $APP_BIN 0x10000 verify")
    # Fix PCR_UART0_SCLK_CONF_REG: ESP-IDF disables UART0 SCLK when USB-JTAG
    # console is active; without this bit22 the ROM hangs at 0x4003B10E.
    OOCD_CMDS+=("-c" "mww 0x60096004 0x00400000")
    # JTAG CPU reset (cause 24) always parks the ROM in download mode.
    OOCD_CMDS+=("-c" "reset run")
    OOCD_CMDS+=("-c" "sleep 1000")
    OOCD_CMDS+=("-c" "exit")
    "$OOCD_BIN" -s "$OOCD_SCRIPTS" -f board/esp32c5-builtin.cfg "${OOCD_CMDS[@]}"

    # 2. esptool: ROM is in download mode. USBJTAGSerialReset (--before
    #    default_reset) wakes it; --after hard_reset exits download mode
    #    and boots the freshly-flashed app.
    fuser -k "$PORT" >/dev/null 2>&1 || true
    sleep 0.5
    ESPTOOL_ARGS=(
        --chip esp32c5 -p "$PORT" -b 115200
        --before default_reset --after hard_reset --no-stub
        chip_id
    )
    python3 -m esptool "${ESPTOOL_ARGS[@]}" 2>&1 \
        | grep -v '^Writing\|^Erasing\|^Wrote\|^Hash\|^Took'
fi

if [[ "$DO_RESET" == 1 && "$DO_FLASH" == 0 ]]; then
    fuser -k "$PORT" >/dev/null 2>&1 || true
    sleep 0.3
    python3 - "$PORT" <<'PYEOF'
import os, sys, fcntl, struct, termios, time
port = sys.argv[1]
fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
attrs = termios.tcgetattr(fd)
attrs[0]=0; attrs[1]=0
attrs[2]=termios.CS8|termios.CREAD|termios.CLOCAL; attrs[3]=0
attrs[4]=termios.B115200; attrs[5]=termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, attrs)
fcntl.ioctl(fd, 0x5418, struct.pack("I", 0))
os.write(fd, b"reset\n")
time.sleep(0.3)
try:
    d = os.read(fd, 4096)
    if d: sys.stdout.write(d.decode("utf-8", errors="replace"))
except BlockingIOError:
    pass
os.close(fd)
PYEOF
fi
