#!/usr/bin/env python3
"""Verify WASIp1 symlinks in both engines with the process privilege removed."""
from __future__ import annotations

import ctypes
from ctypes import wintypes
import json
import os
from pathlib import Path
import subprocess
import tempfile

from native_process import executable

ROOT = Path(__file__).resolve().parents[1]


def remove_process_symlink_privilege() -> None:
    class Luid(ctypes.Structure):
        _fields_ = [("low", wintypes.DWORD), ("high", wintypes.LONG)]

    class Privileges(ctypes.Structure):
        _fields_ = [("count", wintypes.DWORD), ("luid", Luid), ("attributes", wintypes.DWORD)]

    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    api = ctypes.WinDLL("advapi32", use_last_error=True)
    kernel.GetCurrentProcess.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    api.OpenProcessToken.argtypes = [wintypes.HANDLE, wintypes.DWORD, ctypes.POINTER(wintypes.HANDLE)]
    api.LookupPrivilegeValueW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR, ctypes.POINTER(Luid)]
    api.AdjustTokenPrivileges.argtypes = [wintypes.HANDLE, wintypes.BOOL, ctypes.POINTER(Privileges),
                                        wintypes.DWORD, ctypes.c_void_p, ctypes.c_void_p]
    token = wintypes.HANDLE()
    if not api.OpenProcessToken(kernel.GetCurrentProcess(), 0x28, ctypes.byref(token)):
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        privileges = Privileges(count=1, attributes=4)  # SE_PRIVILEGE_REMOVED
        if not api.LookupPrivilegeValueW(None, "SeCreateSymbolicLinkPrivilege", ctypes.byref(privileges.luid)):
            raise ctypes.WinError(ctypes.get_last_error())
        ctypes.set_last_error(0)
        if not api.AdjustTokenPrivileges(token, False, ctypes.byref(privileges), 0, None, None):
            raise ctypes.WinError(ctypes.get_last_error())
        if ctypes.get_last_error() not in (0, 1300):  # Already absent is also acceptable.
            raise ctypes.WinError(ctypes.get_last_error())
    finally:
        kernel.CloseHandle(token)


def guest(expected: int) -> str:
    return f'''(module
      (import "wasi_snapshot_preview1" "path_symlink" (func $symlink (param i32 i32 i32 i32 i32) (result i32)))
      (import "wasi_snapshot_preview1" "path_readlink" (func $readlink (param i32 i32 i32 i32 i32 i32) (result i32)))
      (memory (export "memory") 1)
      (data (i32.const 0) "missing")
      (data (i32.const 16) "link")
      (func $assert (param i32) (if (i32.eqz (local.get 0)) (then unreachable)))
      (func (export "_start")
        (call $assert (i32.eq
          (call $symlink (i32.const 0) (i32.const 7) (i32.const 3) (i32.const 16) (i32.const 4))
          (i32.const {expected})))
        {'return' if expected else ''}
        (call $assert (i32.eqz (call $readlink (i32.const 3) (i32.const 16) (i32.const 4)
          (i32.const 32) (i32.const 16) (i32.const 64))))
        (call $assert (i32.eq (i32.load (i32.const 64)) (i32.const 7)))
        (call $assert (i32.eq (i32.load (i32.const 32)) (i32.const 0x7373696d)))
        (call $assert (i32.eq (i32.load (i32.const 35)) (i32.const 0x676e6973)))))'''


def main() -> None:
    mode = os.environ["WASMOON_TEST_DEVELOPER_MODE"]
    assert mode in ("0", "1") and os.name == "nt"
    results = []
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        wat = root / "symlink.wat"
        wasm = wat.with_suffix(".wasm")
        wat.write_text(guest(0 if mode == "1" else 63))  # WASI ERRNO_PERM
        subprocess.run(["wasm-tools", "parse", str(wat), "-o", str(wasm)], check=True)
        # Removal is intentionally irreversible and confined to this test process
        # and its subsequently launched guests; the CI runner token is unaffected.
        remove_process_symlink_privilege()
        for engine in ("jit", "interp"):
            scratch = root / engine
            scratch.mkdir()
            command = [str(executable(ROOT, "wasmoon")), "run", str(wasm), "--dir", f"{scratch}::."]
            if engine == "interp":
                command.append("--no-jit")
            completed = subprocess.run(command, capture_output=True, text=True, timeout=30)
            exists = os.path.lexists(scratch / "link")
            passed = completed.returncode == 0 and exists == (mode == "1")
            result = dict(engine=engine, developer_mode=mode, passed=passed,
                          returncode=completed.returncode, stderr=completed.stderr)
            results.append(result)
            print(json.dumps(result), flush=True)
    output = ROOT / f"target/windows-symlinks-{mode}.json"
    output.write_text(json.dumps(results, indent=2) + "\n")
    if not all(result["passed"] for result in results):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
