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


def run_logged(command: list[str], path: Path, timeout: float) -> dict:
    started = time.monotonic()
    with path.open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=log,
                                   start_new_session=True)
        timed_out = False
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            kill_process_tree(process)
            code = process.wait()
    result = dict(returncode=code, timed_out=timed_out,
                  seconds=round(time.monotonic() - started, 3), log=str(path))
    print(json.dumps(result), flush=True)
    print(path.read_text(encoding="utf-8", errors="replace")[-16000:], flush=True)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=300)
    parser.add_argument("--output", type=Path, default=ROOT / "target/native-packages")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    print("Building complete native test inventory (two compiler workers)", flush=True)
    build = run_logged(["moon", "test", "--target", "native", "--jobs", "2", "--build-only"],
                       args.output / "build.log", 900)
    evidence = dict(build=build, inventory_count=0, packages=[])
    summary = args.output / "results.json"
    summary.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    if build["returncode"] or build["timed_out"]:
        return 1
    inventory = subprocess.run(["moon", "test", "--target", "native", "--outline"],
                               cwd=ROOT, check=True, capture_output=True, text=True,
                               encoding="utf-8", timeout=60).stdout
    (args.output / "inventory.txt").write_text(inventory, encoding="utf-8")
    entries = re.findall(r"^\s*(\d+)\. (\S+) ", inventory, re.MULTILINE)
    if not entries or [int(i) for i, _ in entries] != list(range(1, len(entries) + 1)):
        raise RuntimeError("Native test inventory is empty or incomplete")
    evidence["inventory_count"] = len(entries)
    packages = list(dict.fromkeys(package for _, package in entries))
    for package in packages:
        print(f"Running {package}", flush=True)
        log_path = args.output / (package.replace("/", "_") + ".log")
        result = run_logged(["moon", "test", "--target", "native", "--no-parallelize",
                             "--jobs", "2", "--package", package], log_path, args.timeout)
        result["package"] = package
        result["expected_tests"] = sum(name == package for _, name in entries)
        counts = re.findall(r"Total tests: (\d+),", log_path.read_text(encoding="utf-8", errors="replace"))
        result["executed_tests"] = int(counts[-1]) if counts else 0
        if result["executed_tests"] != result["expected_tests"]:
            result["returncode"] = result["returncode"] or 1
        evidence["packages"].append(result)
        summary.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    return int(any(result["returncode"] or result["timed_out"] for result in evidence["packages"]))


if __name__ == "__main__":
    raise SystemExit(main())
