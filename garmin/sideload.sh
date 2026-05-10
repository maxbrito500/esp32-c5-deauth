#!/usr/bin/env bash
#
# Sideload bin/deauther.prg to a connected Garmin watch over USB MTP.
# The watch must be set to "MTP (Media Transfer)" mode in its USB settings.
#
set -euo pipefail
cd "$(dirname "$0")"

PRG="bin/deauther.prg"
if [ ! -f "$PRG" ]; then
    echo "No build found at $PRG. Run ./run-fenix7pro.sh first."
    exit 1
fi

# Find the gvfs MTP mount for any Garmin device (vendor 091e)
MTP_MOUNT=$(ls /run/user/$(id -u)/gvfs/ 2>/dev/null | grep "mtp:host=091e_" | head -1)

if [ -z "$MTP_MOUNT" ]; then
    echo "No Garmin watch found over MTP."
    echo "Check:"
    echo "  1. Watch is plugged in via USB-C (data cable, not charge-only)"
    echo "  2. Watch USB mode is set to 'MTP (Media Transfer)'"
    echo "  3. Watch may take a few seconds to enumerate after plugging in"
    echo
    echo "lsusb output:"
    lsusb | grep -i garmin || echo "  (no Garmin device on USB)"
    exit 1
fi

MTP_PATH="/run/user/$(id -u)/gvfs/$MTP_MOUNT"
APPS_DIR="$MTP_PATH/Internal Storage/GARMIN/Apps"

if [ ! -d "$APPS_DIR" ]; then
    echo "Apps folder not found at: $APPS_DIR"
    echo "Watch filesystem layout may differ. Listing GARMIN root:"
    ls "$MTP_PATH/Internal Storage/GARMIN/" 2>/dev/null | head
    exit 1
fi

echo "Watch found: $MTP_MOUNT"
echo "Copying $PRG to watch..."
gio copy "$PRG" "$APPS_DIR/deauther.prg"

# Verify
SIZE_LOCAL=$(stat -c %s "$PRG")
SIZE_WATCH=$(stat -c %s "$APPS_DIR/deauther.prg" 2>/dev/null || echo 0)
if [ "$SIZE_LOCAL" = "$SIZE_WATCH" ]; then
    echo "OK: $SIZE_WATCH bytes copied to watch."
    echo "Unplug the watch and open: Activities & Apps -> Deauther"
else
    echo "WARN: size mismatch (local=$SIZE_LOCAL, watch=$SIZE_WATCH)"
    exit 1
fi
