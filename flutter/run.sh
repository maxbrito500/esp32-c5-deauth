#!/usr/bin/env bash
# Launch the ESP32-C5 Deauther Flutter app on the Linux desktop.
set -euo pipefail

FLUTTER="/home/brito/flutter/bin/flutter"
DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$DIR"

# Install/sync dependencies if needed
"$FLUTTER" pub get --suppress-analytics

exec "$FLUTTER" run -d linux --suppress-analytics "$@"
