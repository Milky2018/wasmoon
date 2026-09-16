#!/usr/bin/env python3
"""Execute WASIp1 mixed clock/fd subscriptions through both native engines."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time

from native_process import executable, kill_process_tree

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = b"x\r\n\x1a"


def guest(scenario: str) -> str:
    clock = scenario == "pending-clock"
    invalid = scenario == "invalid-fd"
    eof = scenario == "pipe-eof"
    duplicate = scenario == "duplicate-read"
    read_assertions = "" if clock or invalid else f'''
        (i32.store (i32.const 320) (i32.const 384))
        (i32.store (i32.const 324) (i32.const 4))
        (call $assert (i32.eqz (call $read (i32.const 0) (i32.const 320) (i32.const 1) (i32.const 328))))
        (call $assert (i32.eq (i32.load (i32.const 328)) (i32.const {0 if eof else 4})))
        {"" if eof else "(call $assert (i32.eq (i32.load (i32.const 384)) (i32.const 0x1a0a0d78)))"}'''
    extra_subscription = "" if not duplicate else '''
        (i64.store (i32.const 96) (i64.const 3))
        (i32.store8 (i32.const 104) (i32.const 1))'''
    extra_assertions = "" if not duplicate else '''
        (call $assert (i64.eq (i64.load (i32.const 160)) (i64.const 3)))
        (call $assert (i32.eqz (i32.load16_u (i32.const 168))))
        (call $assert (i32.eq (i32.load8_u (i32.const 170)) (i32.const 1)))'''
    return f'''(module
      (import "wasi_snapshot_preview1" "poll_oneoff" (func $poll (param i32 i32 i32 i32) (result i32)))
      (import "wasi_snapshot_preview1" "fd_read" (func $read (param i32 i32 i32 i32) (result i32)))
      (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
      (memory (export "memory") 1)
      (func $assert (param $condition i32)
        (if (i32.eqz (local.get $condition)) (then (call $exit (i32.const 1)) unreachable)))
      (func (export "_start")
        (i64.store (i32.const 0) (i64.const 1))
        (i32.store (i32.const 16) (i32.const 1))
        (i64.store (i32.const 24) (i64.const {20_000_000 if clock else 5_000_000_000}))
        (i64.store (i32.const 48) (i64.const 2))
        (i32.store8 (i32.const 56) (i32.const 1))
        (i32.store (i32.const 64) (i32.const {123456 if invalid else 0}))
        {extra_subscription}
        (call $assert (i32.eq (call $poll (i32.const 0) (i32.const 128) (i32.const {3 if duplicate else 2}) (i32.const 256)) (i32.const {8 if invalid else 0})))
        {"return" if invalid else ""}
        (call $assert (i32.eq (i32.load (i32.const 256)) (i32.const {2 if duplicate else 1})))
        (call $assert (i64.eq (i64.load (i32.const 128)) (i64.const {1 if clock else 2})))
        (call $assert (i32.eq (i32.load16_u (i32.const 136)) (i32.const {8 if invalid else 0})))
        (call $assert (i32.eq (i32.load8_u (i32.const 138)) (i32.const {0 if clock else 1})))
        {"(call $assert (i32.eq (i32.load16_u (i32.const 152)) (i32.const 1)))" if eof else ""}
        {extra_assertions}
        {read_assertions}
        (call $exit (i32.const 0))))'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wasmoon", type=Path, default=executable(ROOT, "wasmoon"))
    parser.add_argument("--output", type=Path, default=ROOT / "target/windows-readiness.json")
    args = parser.parse_args()
    results = []
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        scenarios = ("pending-clock", "delayed-pipe", "regular-file", "pipe-eof", "invalid-fd", "duplicate-read")
        for scenario in scenarios:
            source = root / f"{scenario}.wat"
            source.write_text(guest(scenario))
            subprocess.run(["wasm-tools", "parse", str(source), "-o", str(source.with_suffix(".wasm"))], check=True)
        for mode in ("jit", "interp"):
            for scenario in scenarios:
                wasm = root / f"{scenario}.wasm"
                command = [str(args.wasmoon.resolve()), "run", str(wasm)]
                if mode == "interp": command.append("--no-jit")
                input_file = None
                if scenario == "regular-file":
                    input_file = tempfile.TemporaryFile()
                    input_file.write(PAYLOAD)
                    input_file.seek(0)
                environment = os.environ | {"WASMOON_JIT_CACHE_DIR": str(root / f"cache-{mode}-{scenario}")}
                process = subprocess.Popen(command, stdin=input_file or subprocess.PIPE,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment,
                    start_new_session=True)
                started = time.monotonic()
                timer = None
                if scenario in ("delayed-pipe", "duplicate-read"):
                    def deliver():
                        try:
                            process.stdin.write(PAYLOAD)
                            process.stdin.flush()
                        except (BrokenPipeError, OSError):
                            pass
                    timer = threading.Timer(0.05, deliver)
                    timer.start()
                if scenario == "pipe-eof":
                    process.stdin.close()
                try:
                    # Keep the pipe open during poll: communicate() would close
                    # stdin and turn the pending-clock case into an EOF event.
                    code = process.wait(timeout=10)
                    elapsed = time.monotonic() - started
                    stdout, stderr = process.stdout.read(), process.stderr.read()
                    passed = code == 0 and (scenario != "pending-clock" or elapsed >= 0.015)
                    result = dict(mode=mode, scenario=scenario, passed=passed, returncode=code,
                                  seconds=elapsed, stdout=stdout.decode(errors="replace"),
                                  stderr=stderr.decode(errors="replace"))
                except subprocess.TimeoutExpired:
                    kill_process_tree(process)
                    process.wait()
                    result = dict(mode=mode, scenario=scenario, passed=False, error="guest timed out")
                finally:
                    if timer: timer.join()
                    if process.stdin: process.stdin.close()
                    process.stdout.close(); process.stderr.close()
                    if input_file: input_file.close()
                results.append(result)
                print(json.dumps(result), flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, indent=2) + "\n")
    return int(not all(result["passed"] for result in results))


if __name__ == "__main__":
    raise SystemExit(main())
