#!/usr/bin/env bash
# Interactive serial console wrapper. Just runs tools/serial_console.py with
# the port freed of any stale process. See that file for behavior details.

set -euo pipefail

PORT="${PORT:-/dev/ttyACM0}"

fuser -k "$PORT" >/dev/null 2>&1 || true
sleep 0.2

DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$DIR/tools/serial_console.py" "$PORT"
