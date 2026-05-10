#!/usr/bin/env bash
#
# Start the Connect IQ simulator in the foreground.
# Run this FIRST in one terminal, then run ./run.sh in another.
# Keep this terminal open while you work — closing it kills the simulator.
#
set -euo pipefail

SDK="$HOME/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-8.4.1-2026-02-03-e9f77eeaa"
SIMULATOR="$SDK/bin/simulator"

if pgrep -f "ConnectIQ.*bin/simulator" > /dev/null; then
    echo "Simulator is already running."
    exit 0
fi

echo "Starting Connect IQ simulator..."
echo "Keep this terminal open. Press Ctrl-C to stop."

# The Garmin simulator segfaults under hardware GL on many Linux setups.
# Force software rendering — slower but stable.
export LIBGL_ALWAYS_SOFTWARE=1

exec "$SIMULATOR"
