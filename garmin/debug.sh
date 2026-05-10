#!/usr/bin/env bash
#
# Debug helper: rebuild, kill any running simulator, start a fresh one with
# software rendering, load the app, capture everything to /tmp/deauther-debug.log
# so Claude can read it directly. No need to paste output.
#
set -uo pipefail
cd "$(dirname "$0")"

SDK="$HOME/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-8.4.1-2026-02-03-e9f77eeaa"
MONKEYC="$SDK/bin/monkeyc"
SIMULATOR="$SDK/bin/simulator"
MONKEYDO="$SDK/bin/monkeydo"
KEY="developer_key.der"
PRG="bin/deauther.prg"
DEVICE="${DEAUTHER_DEVICE:-fenix7pro}"
SIM_LOG="/tmp/ciq-sim.log"
FULL_LOG="/tmp/deauther-debug.log"

# Reset full log
{
  echo "=== $(date) ==="
  echo "=== device: $DEVICE ==="
} > "$FULL_LOG"

log() {
    echo "$@" | tee -a "$FULL_LOG"
}

log "=== building ==="
if "$MONKEYC" -d "$DEVICE" -f monkey.jungle -o "$PRG" -y "$KEY" -w 2>&1 | tee -a "$FULL_LOG"; then
    log "build OK"
else
    log "BUILD FAILED"
    echo "Log: $FULL_LOG"
    exit 1
fi

log "=== killing any running simulator ==="
pkill -f bin/simulator 2>/dev/null || true
sleep 2

log "=== starting simulator (software GL) ==="
LIBGL_ALWAYS_SOFTWARE=1 "$SIMULATOR" > "$SIM_LOG" 2>&1 &
SIM=$!
sleep 5

if ! kill -0 "$SIM" 2>/dev/null; then
    log "simulator died on startup"
    log "--- sim log ---"
    cat "$SIM_LOG" >> "$FULL_LOG"
    cat "$SIM_LOG"
    echo "Log: $FULL_LOG"
    exit 1
fi
log "simulator alive (pid $SIM)"

log "=== loading app ==="
"$MONKEYDO" "$PRG" "$DEVICE" 2>&1 | tee -a "$FULL_LOG"
sleep 3

log ""
if kill -0 "$SIM" 2>/dev/null; then
    log "=== sim alive after monkeydo: YES ==="
else
    log "=== sim alive after monkeydo: NO (crashed) ==="
fi

log ""
log "=== full simulator log ==="
cat "$SIM_LOG" | tee -a "$FULL_LOG"

log ""
log "=== Log saved to $FULL_LOG ==="
log "(to stop simulator: pkill -f bin/simulator)"
