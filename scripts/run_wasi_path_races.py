#!/usr/bin/env python3
"""Exercise Preview 1 directory capabilities under concurrent path replacement."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading

from native_process import executable

ROOT = Path(__file__).resolve().parents[1]
GUEST = r'''(module
  (import "wasi_snapshot_preview1" "fd_read" (func $read (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write" (func $write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_close" (func $close (param i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_open" (func $open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_filestat_get" (func $stat (param i32 i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_filestat_set_times" (func $times (param i32 i32 i32 i32 i64 i64 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 0) "slot/file")
  (func (export "_start") (local $i i32) (local $ok i32)
    ;; Signal that preopens are installed, then wait for the host race thread.
    (i32.store (i32.const 32) (i32.const 64))
    (i32.store (i32.const 36) (i32.const 1))
    (drop (call $write (i32.const 1) (i32.const 32) (i32.const 1) (i32.const 40)))
    (drop (call $read (i32.const 0) (i32.const 32) (i32.const 1) (i32.const 40)))
    (loop $again
      (if (i32.eqz (call $open (i32.const 3) (i32.const 1) (i32.const 0) (i32.const 9)
            (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0) (i32.const 48)))
        (then (local.set $ok (i32.add (local.get $ok) (i32.const 1)))
          (drop (call $close (i32.load (i32.const 48))))))
      (drop (call $stat (i32.const 3) (i32.const 1) (i32.const 0) (i32.const 9) (i32.const 128)))
      (drop (call $times (i32.const 3) (i32.const 1) (i32.const 0) (i32.const 9)
        (i64.const 0) (i64.const 0) (i32.const 10)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $again (i32.lt_u (local.get $i) (i32.const 5000))))
    (i32.store (i32.const 64) (local.get $ok))
    (i32.store (i32.const 36) (i32.const 4))
    (drop (call $write (i32.const 1) (i32.const 32) (i32.const 1) (i32.const 40)))))'''


def run(engine: str, mutation: str, wasm: Path, root: Path) -> dict:
    sandbox = root / (engine + "-" + mutation)
    sandbox.mkdir()
    slot = sandbox / "slot"
    slot.mkdir()
    outside = root / (engine + "-" + mutation + "-outside")
    outside.mkdir()
    sentinel = outside / "file"
    sentinel.write_bytes(b"outside capability")
    os.utime(sentinel, ns=(1_000_000_000, 1_000_000_000))
    before = sentinel.stat()
    if mutation == "leaf":
        slot = slot / "file"
        slot.write_bytes(b"inside")
    parked = slot.with_name("parked")
    replacement_target = outside if mutation == "ancestor" else sentinel
    command = [str(executable(ROOT, "wasmoon")), "run", str(wasm), "--dir", f"{sandbox}::."]
    if engine == "interp":
        command.append("--no-jit")
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stop = threading.Event()
    counts = dict(replacements=0, denied_renames=0, contended_creates=0)
    errors = []

    def retry_mutation(operation) -> bool:
        while not stop.is_set():
            try:
                operation()
                return True
            except PermissionError:
                # Windows may keep a file delete-pending while a guest holds it.
                # This is contention, not a failed isolation assertion.
                counts["denied_renames"] += 1
                stop.wait(0.001)
        return False

    def replace() -> None:
        try:
            while not stop.is_set():
                if not retry_mutation(lambda: slot.rename(parked)):
                    break
                try:
                    try:
                        slot.symlink_to(replacement_target, target_is_directory=mutation == "ancestor")
                    except FileExistsError:
                        counts["contended_creates"] += 1
                    except PermissionError:
                        # O_CREAT can win the missing-leaf race with a live handle.
                        if mutation != "leaf" or not slot.exists():
                            raise
                        counts["contended_creates"] += 1
                    else:
                        counts["replacements"] += 1
                finally:
                    def restore():
                        if slot.is_symlink() or (mutation == "leaf" and slot.exists()):
                            slot.unlink()
                        parked.replace(slot)
                    restored = retry_mutation(restore)
                if not restored:
                    break
        except Exception as error:
            errors.append(repr(error))

    watchdog = threading.Timer(60, process.kill)
    watchdog.start()
    thread = threading.Thread(target=replace)
    try:
        if process.stdout.read(1) != b"\0":
            raise RuntimeError("guest did not reach the preopen handshake")
        thread.start()
        process.stdin.write(b"x")
        process.stdin.flush()
        output, stderr = process.communicate(timeout=60)
    finally:
        stop.set()
        if thread.ident is not None:
            thread.join(timeout=10)
        watchdog.cancel()
        if process.poll() is None:
            process.kill()
        process.wait()
    after = sentinel.stat()
    successful_opens = int.from_bytes(output, "little") if len(output) == 4 else 0
    passed = (process.returncode == 0 and successful_opens > 0 and not errors and
              not thread.is_alive() and counts["replacements"] > 0 and
              after.st_size == before.st_size and after.st_mtime_ns == before.st_mtime_ns and
              sentinel.read_bytes() == b"outside capability")
    return dict(engine=engine, mutation=mutation, passed=passed, successful_opens=successful_opens,
                **counts, errors=errors, outside_size=after.st_size,
                outside_mtime_ns=after.st_mtime_ns, returncode=process.returncode,
                stdout_hex=output.hex(), stderr=stderr.decode(errors="replace"))


def main() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        wat = root / "paths.wat"
        wasm = wat.with_suffix(".wasm")
        wat.write_text(GUEST)
        subprocess.run(["wasm-tools", "parse", str(wat), "-o", str(wasm)], check=True)
        results = [run(engine, mutation, wasm, root)
                   for engine in ("jit", "interp") for mutation in ("ancestor", "leaf")]
    output = ROOT / "target/wasi-path-races.json"
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(results, indent=2) + "\n")
    for result in results:
        print(json.dumps(result), flush=True)
    if not all(result["passed"] for result in results):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
