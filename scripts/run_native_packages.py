#!/usr/bin/env python3
"""Run the complete native test inventory with a bounded wait per package."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import time

from native_process import kill_process_tree

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=300)
    parser.add_argument("--output", type=Path, default=ROOT / "target/native-packages")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    subprocess.run(["moon", "test", "--target", "native", "--build-only"], cwd=ROOT, check=True)
    inventory = subprocess.run(["moon", "test", "--target", "native", "--outline"],
                               cwd=ROOT, check=True, capture_output=True, text=True).stdout
    (args.output / "inventory.txt").write_text(inventory)
    entries = re.findall(r"^\s*(\d+)\. (\S+) ", inventory, re.MULTILINE)
    if not entries or [int(i) for i, _ in entries] != list(range(1, len(entries) + 1)):
        raise RuntimeError("Native test inventory is empty or incomplete")
    packages = list(dict.fromkeys(package for _, package in entries))
    results = []
    for package in packages:
        print(f"Running {package}", flush=True)
        log_path = args.output / (package.replace("/", "_") + ".log")
        started = time.monotonic()
        with log_path.open("w") as log:
            process = subprocess.Popen(["moon", "test", "--target", "native", "--no-parallelize",
                                        "--package", package], cwd=ROOT, stdout=log, stderr=log,
                                       start_new_session=True)
            timed_out = False
            try:
                code = process.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                kill_process_tree(process)
                code = process.wait()
        result = dict(package=package, returncode=code, timed_out=timed_out,
                      seconds=round(time.monotonic() - started, 3), log=str(log_path))
        results.append(result)
        print(json.dumps(result), flush=True)
        if code or timed_out:
            print(log_path.read_text(errors="replace")[-16000:], flush=True)
        (args.output / "results.json").write_text(json.dumps(
            dict(inventory_count=len(entries), packages=results), indent=2) + "\n")
    return int(any(result["returncode"] or result["timed_out"] for result in results))


if __name__ == "__main__":
    raise SystemExit(main())
