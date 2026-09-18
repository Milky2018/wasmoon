#!/usr/bin/env python3
"""Check physical allocation and sparse-file rejection through both P1 engines."""
from __future__ import annotations

import ctypes
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

from native_process import executable

ROOT = Path(__file__).resolve().parents[1]
GUEST = r'''(module
(import "wasi_snapshot_preview1" "path_open" (func $open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "fd_allocate" (func $allocate (param i32 i64 i64) (result i32)))
(import "wasi_snapshot_preview1" "fd_seek" (func $seek (param i32 i64 i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "fd_tell" (func $tell (param i32 i32) (result i32)))
(memory (export "memory") 1) (data (i32.const 64) "file")
(func (export "probe") (result i32) (local $fd i32) (local $errno i32)
 (if (call $open (i32.const 3) (i32.const 0) (i32.const 64) (i32.const 4) (i32.const 0)
       (i64.const 358) (i64.const 0) (i32.const 0) (i32.const 0)) (then unreachable))
 (local.set $fd (i32.load (i32.const 0)))
 (if (call $seek (local.get $fd) (i64.const 7) (i32.const 0) (i32.const 16)) (then unreachable))
 (local.set $errno (call $allocate (local.get $fd) (i64.const OFFSET) (i64.const LENGTH)))
 (if (call $tell (local.get $fd) (i32.const 16)) (then unreachable))
 (if (i64.ne (i64.load (i32.const 16)) (i64.const 7)) (then unreachable))
 (local.get $errno)))'''


def punch_hole(fd: int) -> None:
    if sys.platform == "darwin":
        import fcntl
        fcntl.fcntl(fd, 99, struct.pack("IIqq", 0, 0, 0, 65536))  # F_PUNCHHOLE
    elif sys.platform == "win32":
        import msvcrt
        from ctypes import wintypes
        ioctl = ctypes.WinDLL("kernel32", use_last_error=True).DeviceIoControl
        ioctl.argtypes = [wintypes.HANDLE, wintypes.DWORD, ctypes.c_void_p,
                          wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD,
                          ctypes.POINTER(wintypes.DWORD), ctypes.c_void_p]
        ioctl.restype = wintypes.BOOL
        handle = msvcrt.get_osfhandle(fd)
        returned = wintypes.DWORD()
        zero_range = ctypes.create_string_buffer(struct.pack("qq", 0, 65536))
        for code, buf, size in [(0x900C4, None, 0), (0x980C8, zero_range, 16)]:
            if not ioctl(handle, code, buf, size, None, 0, ctypes.byref(returned), None):
                raise ctypes.WinError(ctypes.get_last_error())
    else:
        libc = ctypes.CDLL(None, use_errno=True)
        libc.fallocate.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_longlong]
        if libc.fallocate(fd, 3, 0, 65536) != 0:  # PUNCH_HOLE | KEEP_SIZE
            raise OSError(ctypes.get_errno(), "fallocate(PUNCH_HOLE)")


def allocation_size(path: Path) -> int:
    if sys.platform != "win32":
        return path.stat().st_blocks * 512
    from ctypes import wintypes
    api = ctypes.WinDLL("kernel32", use_last_error=True).GetCompressedFileSizeW
    api.argtypes = [wintypes.LPCWSTR, ctypes.POINTER(wintypes.DWORD)]
    api.restype = wintypes.DWORD
    high = wintypes.DWORD()
    ctypes.set_last_error(0)
    low = api(str(path), ctypes.byref(high))
    if low == 0xFFFFFFFF and ctypes.get_last_error():
        raise ctypes.WinError(ctypes.get_last_error())
    return (high.value << 32) | low


def run(engine: str, sparse: bool, root: Path) -> dict:
    directory = root / f"{engine}-{'sparse' if sparse else 'dense'}"
    directory.mkdir()
    path = directory / "file"
    with path.open("wb") as stream:
        stream.write(b"x" * 131072)
        stream.flush()
        os.fsync(stream.fileno())
        if sparse:
            punch_hole(stream.fileno())
            os.fsync(stream.fileno())
    before = path.read_bytes()
    allocated_before = allocation_size(path)
    if sparse:
        assert before == b"\0" * 65536 + b"x" * 65536
        assert allocated_before < len(before), "sparse fixture has no physical hole"
    offset, length = (0, 4096) if sparse else (1048576, 65536)
    guest = directory / "probe.wat"
    guest.write_text(GUEST.replace("OFFSET", str(offset)).replace("LENGTH", str(length)))
    command = [str(executable(ROOT, "wasmoon")), "run", str(guest), "--invoke", "probe", "--dir", str(directory)]
    if engine == "interp":
        command.append("--no-jit")
    completed = subprocess.run(command, capture_output=True, text=True, timeout=30)
    expected = 58 if sparse and sys.platform in ("darwin", "win32") else 0
    after = path.read_bytes()
    allocated_after = allocation_size(path)
    checks = [completed.returncode == 0, completed.stdout.strip() == str(expected),
              after[:len(before)] == before]
    if sparse:
        checks.append(len(after) == len(before))
        checks.append(allocated_after == allocated_before if expected == 58 else allocated_after > allocated_before)
    else:
        checks.extend([len(after) == offset + length, allocated_after >= allocated_before + length,
                       after[len(before):] == b"\0" * (offset + length - len(before))])
    return dict(engine=engine, sparse=sparse, passed=all(checks), expected_errno=expected,
                allocated_before=allocated_before, allocated_after=allocated_after,
                size_after=len(after), command=command, returncode=completed.returncode,
                stdout=completed.stdout, stderr=completed.stderr)


def main() -> int:
    results = []
    with tempfile.TemporaryDirectory(prefix="wasmoon-allocation-") as directory:
        for engine in ("interp", "jit"):
            for sparse in (False, True):
                result = run(engine, sparse, Path(directory))
                results.append(result)
                print(json.dumps(result), flush=True)
    output = ROOT / "target/wasi-allocation.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(results, indent=2) + "\n")
    return 0 if all(result["passed"] for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
