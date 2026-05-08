#!/usr/bin/env python3
"""Interactive serial console for the XIAO ESP32-C5 deauther.

Reads/writes a CDC ACM port at 115200 baud, with DTR and RTS held LOW so
the chip's USB-Serial-JTAG controller does not mis-strap BOOT on this
board. Background thread streams device output to stdout; main thread
forwards stdin lines (each terminated with \\n) to the device.

Usage:
    ./tools/serial_console.py                 # default port /dev/ttyACM0
    ./tools/serial_console.py /dev/ttyACM1
    PORT=/dev/ttyACM1 ./tools/serial_console.py
"""

import fcntl
import os
import signal
import struct
import sys
import termios
import threading
import time

DEFAULT_PORT = "/dev/ttyACM0"
TIOCMSET = 0x5418


def configure_port(fd):
    attrs = termios.tcgetattr(fd)
    attrs[0] = 0
    attrs[1] = 0
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[3] = 0
    attrs[4] = termios.B115200
    attrs[5] = termios.B115200
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)
    fcntl.ioctl(fd, TIOCMSET, struct.pack("I", 0))


def main():
    port = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("PORT", DEFAULT_PORT)
    try:
        fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    except OSError as e:
        sys.stderr.write(f"open {port}: {e}\n")
        return 1
    configure_port(fd)

    stop = threading.Event()

    def reader():
        while not stop.is_set():
            try:
                data = os.read(fd, 4096)
                if data:
                    sys.stdout.buffer.write(data)
                    sys.stdout.flush()
                else:
                    time.sleep(0.05)
            except BlockingIOError:
                time.sleep(0.05)
            except OSError:
                stop.set()
                return

    threading.Thread(target=reader, daemon=True).start()

    sys.stderr.write(f"[connected to {port} @ 115200 — Ctrl-C to quit]\n")
    sys.stderr.flush()

    def cleanup_and_exit(*_):
        stop.set()
        try:
            os.close(fd)
        except OSError:
            pass
        sys.stderr.write("\n[bye]\n")
        sys.exit(0)

    signal.signal(signal.SIGINT, cleanup_and_exit)
    signal.signal(signal.SIGTERM, cleanup_and_exit)

    try:
        for line in sys.stdin:
            if not line.endswith("\n"):
                line += "\n"
            try:
                os.write(fd, line.encode("utf-8", errors="replace"))
            except (OSError, BlockingIOError) as e:
                sys.stderr.write(f"\n[write failed: {e}]\n")
                break
    except KeyboardInterrupt:
        pass
    cleanup_and_exit()


if __name__ == "__main__":
    sys.exit(main() or 0)
