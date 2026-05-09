#!/usr/bin/env bash
# Build and deploy the deauther Flutter app to a connected Android device.
set -euo pipefail

FLUTTER="/home/brito/flutter/bin/flutter"
DIR="$(cd "$(dirname "$0")" && pwd)"
DEVICE="${DEVICE:-}"
RELEASE=0

usage() {
    cat <<EOF
Usage: $0 [options]
  --release       build in release mode (default: debug)
  -d, --device ID target device ID (default: first connected Android via adb)
  -h, --help      this help
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)  RELEASE=1; shift ;;
        -d|--device) DEVICE="$2"; shift 2 ;;
        -h|--help)  usage ;;
        *) echo "unknown arg: $1"; usage ;;
    esac
done

if [[ -z "$DEVICE" ]]; then
    DEVICE=$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device" {print $1; exit}')
    if [[ -z "$DEVICE" ]]; then
        echo "No Android device detected. Connect one and check: adb devices" >&2
        exit 1
    fi
fi

echo "Target: $DEVICE"

cd "$DIR"
"$FLUTTER" pub get --suppress-analytics

FLAGS=(--suppress-analytics -d "$DEVICE")
[[ "$RELEASE" == 1 ]] && FLAGS+=(--release)

exec "$FLUTTER" run "${FLAGS[@]}"
