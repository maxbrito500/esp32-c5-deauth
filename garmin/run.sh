#!/usr/bin/env bash
#
# Build the Deauther Garmin app and load it in the running simulator.
# Default device: fenix7pro. For other devices use run-<device>.sh.
#
# IMPORTANT: start ./emulator.sh FIRST (in another terminal). This script
# only builds + loads — it will not start the simulator for you.
#
set -euo pipefail
cd "$(dirname "$0")"

DEVICE="${DEAUTHER_DEVICE:-fenix7pro}"

SDK="$HOME/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-8.4.1-2026-02-03-e9f77eeaa"
MONKEYC="$SDK/bin/monkeyc"
MONKEYDO="$SDK/bin/monkeydo"

KEY="developer_key.der"
OUT="bin/deauther.prg"

if [ ! -f "$KEY" ]; then
    echo "Generating developer key..."
    openssl genrsa -out developer_key.pem 4096 2>/dev/null
    openssl pkcs8 -topk8 -inform PEM -outform DER \
        -in developer_key.pem -out "$KEY" -nocrypt
fi

mkdir -p bin

echo "Building for $DEVICE..."
"$MONKEYC" -d "$DEVICE" -f monkey.jungle -o "$OUT" -y "$KEY" -w
echo "Build OK: $OUT"

if ! pgrep -f "ConnectIQ.*bin/simulator" > /dev/null; then
    echo
    echo "ERROR: Connect IQ simulator is not running."
    echo "Open a SECOND terminal and run:"
    echo "    cd $(pwd)"
    echo "    ./emulator.sh"
    echo "Then re-run this script."
    exit 1
fi

echo "Loading app into simulator ($DEVICE)..."
"$MONKEYDO" "$OUT" "$DEVICE"
