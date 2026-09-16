"""Native executable names and bounded cleanup for external test processes."""
from __future__ import annotations

import os
from pathlib import Path
import signal
import subprocess


def executable(root: Path, name: str) -> Path:
    return root / (name + ".exe" if os.name == "nt" else name)


def kill_process_tree(process: subprocess.Popen) -> None:
    if os.name == "nt":
        # Corpus workers may launch tool/guest descendants. Terminate the tree,
        # then reap the direct child through its Popen owner.
        try:
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=10, check=False)
        except subprocess.TimeoutExpired:
            pass
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
            return
        except OSError:
            pass
    try:
        process.kill()
    except OSError:
        pass
