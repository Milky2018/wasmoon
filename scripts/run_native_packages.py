#!/usr/bin/env python3
"""Run the complete native test inventory with a bounded wait per package."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

from native_process import kill_process_tree

ROOT = Path(__file__).resolve().parents[1]


def windows_process_snapshot(path: Path) -> None:
    if os.name != "nt":
        return
    command = ("Get-CimInstance Win32_Process | Where-Object { "
               "$_.Name -match '^(moon|moonc|clang|clang-cl|lld-link|link)\\.exe$' } | "
               "Select-Object Name,ProcessId,ParentProcessId,CommandLine,"
               "KernelModeTime,UserModeTime,WorkingSetSize | ConvertTo-Json -Depth 2")
    try:
        result = subprocess.run(["powershell.exe", "-NoProfile", "-Command", command],
                                capture_output=True, text=True, encoding="utf-8",
                                errors="replace", timeout=20)
        with path.open("a", encoding="utf-8") as output:
            output.write(json.dumps(dict(time=time.time(), returncode=result.returncode,
                                         stdout=result.stdout, stderr=result.stderr)) + "\n")
    except subprocess.TimeoutExpired:
        with path.open("a", encoding="utf-8") as output:
            output.write(json.dumps(dict(time=time.time(), snapshot_timeout=True)) + "\n")


def run_logged(command: list[str], path: Path, timeout: float) -> dict:
    started = time.monotonic()
    with path.open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=log,
                                   start_new_session=True)
        timed_out = False
        while True:
            remaining = timeout - (time.monotonic() - started)
            try:
                code = process.wait(timeout=max(0, min(60, remaining)))
                break
            except subprocess.TimeoutExpired:
                windows_process_snapshot(path.with_suffix(".processes.jsonl"))
                if time.monotonic() - started >= timeout:
                    timed_out = True
                    kill_process_tree(process)
                    code = process.wait()
                    break
    result = dict(returncode=code, timed_out=timed_out,
                  seconds=round(time.monotonic() - started, 3), log=str(path))
    print(json.dumps(result), flush=True)
    print(path.read_text(encoding="utf-8", errors="replace")[-16000:], flush=True)
    return result


def diagnose_crash(package: str, package_log: Path, output: Path) -> None:
    """Isolate tests in a crashed binary without rebuilding or changing its verdict."""
    build = ROOT / "_build/native/debug/test" / package
    log = package_log.read_text(encoding="utf-8", errors="replace")
    deadline = time.monotonic() + 300
    results = []
    output.mkdir(parents=True, exist_ok=True)
    for kind in ("blackbox", "whitebox", "internal"):
        binary = build / (package.rsplit("/", 1)[-1] + f".{kind}_test.exe")
        metadata = build / f"__{kind}_test_info.json"
        if binary.name not in log or not binary.is_file() or not metadata.is_file():
            continue
        for filename, tests in json.loads(metadata.read_text(encoding="utf-8"))["tests"].items():
            for test in tests:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return
                index = test["index"]
                result = run_logged([str(binary), f"{filename}:{index}-{index + 1}"],
                                    output / f"{kind}-{filename}-{index}.log", min(30, remaining))
                result.update(file=filename, index=index, name=test["name"])
                results.append(result)
                (output / "results.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=300)
    parser.add_argument("--output", type=Path, default=ROOT / "target/native-packages")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    print("Building complete native test inventory (two compiler workers)", flush=True)
    build = run_logged(["moon", "test", "--target", "native", "--jobs", "2", "--build-only", "--strip", "--verbose"],
                       args.output / "build.log", 1800)
    evidence = dict(build=build, inventory_count=0, packages=[])
    summary = args.output / "results.json"
    summary.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    if build["returncode"] or build["timed_out"]:
        return 1
    inventory = subprocess.run(["moon", "test", "--target", "native", "--strip", "--outline"],
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
                             "--jobs", "2", "--strip", "--package", package], log_path, args.timeout)
        result["package"] = package
        result["expected_tests"] = sum(name == package for _, name in entries)
        counts = re.findall(r"Total tests: (\d+),", log_path.read_text(encoding="utf-8", errors="replace"))
        result["executed_tests"] = int(counts[-1]) if counts else 0
        if result["executed_tests"] != result["expected_tests"]:
            result["returncode"] = result["returncode"] or 1
        evidence["packages"].append(result)
        summary.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
        if result["returncode"] and result["executed_tests"] != result["expected_tests"]:
            diagnose_crash(package, log_path, args.output / (package.replace("/", "_") + "-isolated"))
    return int(any(result["returncode"] or result["timed_out"] for result in evidence["packages"]))


if __name__ == "__main__":
    raise SystemExit(main())
