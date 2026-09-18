#!/usr/bin/env python3
"""Adapt process lifecycle conventions without changing guest expectations.

The upstream service runner expects successful shutdown after its SIGINT. Async
restores that signal as the process termination reason after joining cancelled
work. Normalize only this requested, signal-terminated service shutdown.
"""
from pathlib import Path
import os
import signal
import subprocess
import sys


def main():
    service = sys.argv[1] == "service"
    argv = sys.argv[2:]
    guest = Path(argv[-1]).resolve()
    argv[-1] = guest.name
    child = subprocess.Popen(argv, cwd=guest.parent)
    interrupted = False

    def stop(signum, _frame):
        nonlocal interrupted
        interrupted = True
        if child.poll() is None:
            child.send_signal(signum)

    signal.signal(signal.SIGINT, stop)
    code = child.wait()
    if service and interrupted and code == -signal.SIGINT:
        return 0
    # CPython sys.exit accepts a signed C int on Windows. Keep the DWORD bits
    # instead of overflowing to -1 and hiding the original native exception.
    if os.name == "nt" and code > 0x7fffffff:
        return code - 0x100000000
    return code if code >= 0 else 128 - code


if __name__ == "__main__":
    sys.exit(main())
