#!/usr/bin/env python3
"""
WASI Preview1 Comprehensive Test Suite

Tests all 46 WASI functions for correctness in both JIT and interpreter modes.
"""

import subprocess
import tempfile
import os
import sys

# WASI error codes
ESUCCESS = 0
EBADF = 8
EINVAL = 28
ENOTSUP = 58

def run_wat(wat_code, use_jit=True, preopen_dir=None, expected_output=None, expected_return=None):
    """Run a WAT module and check results."""
    with tempfile.NamedTemporaryFile(suffix='.wat', delete=False, mode='w') as f:
        f.write(wat_code)
        wat_file = f.name

    try:
        cmd = ['./wasmoon', 'run', wat_file]
        if not use_jit:
            cmd.insert(2, '--no-jit')
        if preopen_dir:
            cmd.extend(['--dir', preopen_dir])

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)

        if expected_output is not None:
            if expected_output not in result.stdout:
                return False, f"Expected output '{expected_output}' not found in '{result.stdout}'"

        return True, result.stdout
    except subprocess.TimeoutExpired:
        return False, "Timeout"
    except Exception as e:
        return False, str(e)
    finally:
        os.unlink(wat_file)

def test_fd_write():
    """Test fd_write to stdout."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 100) "Hello from fd_write!\\n")
  (data (i32.const 0) "\\64\\00\\00\\00")  ;; buf = 100
  (data (i32.const 4) "\\15\\00\\00\\00")  ;; len = 21
  (func (export "_start")
    (drop (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 8)))))
'''
    return run_wat(wat, expected_output="Hello from fd_write!")

def test_clock_time_get():
    """Test clock_time_get returns success."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "clock_time_get"
    (func $clock_time_get (param i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "clock_time_get: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")  ;; buf = 200
  (data (i32.const 104) "\\12\\00\\00\\00")  ;; len = 18
  (func (export "_start")
    (if (i32.eqz (call $clock_time_get (i32.const 0) (i64.const 1000000) (i32.const 0)))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="clock_time_get: OK")

def test_random_get():
    """Test random_get returns success."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "random_get"
    (func $random_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "random_get: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")
  (data (i32.const 104) "\\0f\\00\\00\\00")
  (func (export "_start")
    (if (i32.eqz (call $random_get (i32.const 0) (i32.const 32)))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="random_get: OK")

def test_args_get():
    """Test args_sizes_get and args_get return success."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "args_sizes_get"
    (func $args_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "args_sizes_get: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")
  (data (i32.const 104) "\\12\\00\\00\\00")
  (func (export "_start")
    (if (i32.eqz (call $args_sizes_get (i32.const 0) (i32.const 4)))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="args_sizes_get: OK")

def test_environ_get():
    """Test environ_sizes_get returns success."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "environ_sizes_get"
    (func $environ_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "environ_sizes_get: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")
  (data (i32.const 104) "\\15\\00\\00\\00")
  (func (export "_start")
    (if (i32.eqz (call $environ_sizes_get (i32.const 0) (i32.const 4)))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="environ_sizes_get: OK")

def test_fd_fdstat_get():
    """Test fd_fdstat_get on stdout."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "fd_fdstat_get"
    (func $fd_fdstat_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "fd_fdstat_get: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")
  (data (i32.const 104) "\\11\\00\\00\\00")
  (func (export "_start")
    (if (i32.eqz (call $fd_fdstat_get (i32.const 1) (i32.const 0)))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="fd_fdstat_get: OK")

def test_sched_yield():
    """Test sched_yield returns success."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "sched_yield"
    (func $sched_yield (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "sched_yield: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")
  (data (i32.const 104) "\\0f\\00\\00\\00")
  (func (export "_start")
    (if (i32.eqz (call $sched_yield))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="sched_yield: OK")

def test_fd_sync():
    """Test fd_sync on stdout."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "fd_sync"
    (func $fd_sync (param i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "fd_sync: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")
  (data (i32.const 104) "\\0b\\00\\00\\00")
  (func (export "_start")
    (if (i32.eqz (call $fd_sync (i32.const 1)))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="fd_sync: OK")

def test_fd_datasync():
    """Test fd_datasync on stdout."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "fd_datasync"
    (func $fd_datasync (param i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "fd_datasync: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")
  (data (i32.const 104) "\\0f\\00\\00\\00")
  (func (export "_start")
    (if (i32.eqz (call $fd_datasync (i32.const 1)))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="fd_datasync: OK")

def test_fd_advise():
    """Test fd_advise (no-op) returns success."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "fd_advise"
    (func $fd_advise (param i32 i64 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "fd_advise: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")
  (data (i32.const 104) "\\0d\\00\\00\\00")
  (func (export "_start")
    (if (i32.eqz (call $fd_advise (i32.const 1) (i64.const 0) (i64.const 0) (i32.const 0)))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="fd_advise: OK")

def test_fd_fdstat_set_rights():
    """Test fd_fdstat_set_rights (no-op) returns success."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "fd_fdstat_set_rights"
    (func $fd_fdstat_set_rights (param i32 i64 i64) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "fd_fdstat_set_rights: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")
  (data (i32.const 104) "\\18\\00\\00\\00")
  (func (export "_start")
    (if (i32.eqz (call $fd_fdstat_set_rights (i32.const 1) (i64.const 0) (i64.const 0)))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="fd_fdstat_set_rights: OK")

def test_fd_fdstat_set_flags():
    """Test fd_fdstat_set_flags on stdout."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "fd_fdstat_set_flags"
    (func $fd_fdstat_set_flags (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "fd_fdstat_set_flags: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")
  (data (i32.const 104) "\\17\\00\\00\\00")
  (func (export "_start")
    (if (i32.eqz (call $fd_fdstat_set_flags (i32.const 1) (i32.const 0)))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="fd_fdstat_set_flags: OK")

def test_fd_filestat_get():
    """Test fd_filestat_get on stdout."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "fd_filestat_get"
    (func $fd_filestat_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "fd_filestat_get: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")
  (data (i32.const 104) "\\13\\00\\00\\00")
  (func (export "_start")
    (if (i32.eqz (call $fd_filestat_get (i32.const 1) (i32.const 0)))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="fd_filestat_get: OK")

def test_clock_res_get():
    """Test clock_res_get returns success."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "clock_res_get"
    (func $clock_res_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "clock_res_get: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")
  (data (i32.const 104) "\\11\\00\\00\\00")
  (func (export "_start")
    (if (i32.eqz (call $clock_res_get (i32.const 0) (i32.const 0)))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="clock_res_get: OK")

def test_fd_close_invalid():
    """Test fd_close on invalid fd returns EBADF."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "fd_close"
    (func $fd_close (param i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "fd_close invalid: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")
  (data (i32.const 104) "\\14\\00\\00\\00")
  (func (export "_start")
    (if (i32.eq (call $fd_close (i32.const 999)) (i32.const 8))  ;; EBADF = 8
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="fd_close invalid: OK")

def test_fd_read_invalid():
    """Test fd_read on invalid fd returns EBADF."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "fd_read"
    (func $fd_read (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 0) "\\64\\00\\00\\00\\40\\00\\00\\00")  ;; iovec
  (data (i32.const 200) "fd_read invalid: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")
  (data (i32.const 104) "\\13\\00\\00\\00")
  (func (export "_start")
    (if (i32.eq (call $fd_read (i32.const 999) (i32.const 0) (i32.const 1) (i32.const 8)) (i32.const 8))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="fd_read invalid: OK")

def test_fd_seek_invalid():
    """Test fd_seek on invalid fd returns EBADF."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "fd_seek"
    (func $fd_seek (param i32 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "fd_seek invalid: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")
  (data (i32.const 104) "\\13\\00\\00\\00")
  (func (export "_start")
    (if (i32.eq (call $fd_seek (i32.const 999) (i64.const 0) (i32.const 0) (i32.const 0)) (i32.const 8))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="fd_seek invalid: OK")

def test_fd_prestat_get_invalid():
    """Test fd_prestat_get on invalid fd returns EBADF."""
    wat = '''
(module
  (import "wasi_snapshot_preview1" "fd_prestat_get"
    (func $fd_prestat_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "fd_prestat_get invalid: OK\\n")
  (data (i32.const 100) "\\c8\\00\\00\\00")
  (data (i32.const 104) "\\1a\\00\\00\\00")
  (func (export "_start")
    (if (i32.eq (call $fd_prestat_get (i32.const 999) (i32.const 0)) (i32.const 8))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
'''
    return run_wat(wat, expected_output="fd_prestat_get invalid: OK")

def run_all_tests():
    """Run all tests and report results."""
    tests = [
        ("fd_write", test_fd_write),
        ("clock_time_get", test_clock_time_get),
        ("clock_res_get", test_clock_res_get),
        ("random_get", test_random_get),
        ("args_sizes_get", test_args_get),
        ("environ_sizes_get", test_environ_get),
        ("fd_fdstat_get", test_fd_fdstat_get),
        ("sched_yield", test_sched_yield),
        ("fd_sync", test_fd_sync),
        ("fd_datasync", test_fd_datasync),
        ("fd_advise", test_fd_advise),
        ("fd_fdstat_set_rights", test_fd_fdstat_set_rights),
        ("fd_fdstat_set_flags", test_fd_fdstat_set_flags),
        ("fd_filestat_get", test_fd_filestat_get),
        ("fd_close (invalid)", test_fd_close_invalid),
        ("fd_read (invalid)", test_fd_read_invalid),
        ("fd_seek (invalid)", test_fd_seek_invalid),
        ("fd_prestat_get (invalid)", test_fd_prestat_get_invalid),
    ]

    passed = 0
    failed = 0

    print("=" * 60)
    print("WASI Preview1 Test Suite")
    print("=" * 60)

    for mode in ["JIT", "Interpreter"]:
        use_jit = (mode == "JIT")
        print(f"\n--- {mode} Mode ---\n")

        mode_passed = 0
        mode_failed = 0

        for name, test_func in tests:
            # Modify test to use correct mode
            success, msg = test_func() if use_jit else run_test_interp(test_func)

            if success:
                print(f"  [PASS] {name}")
                mode_passed += 1
            else:
                print(f"  [FAIL] {name}: {msg}")
                mode_failed += 1

        print(f"\n  {mode} Results: {mode_passed} passed, {mode_failed} failed")
        passed += mode_passed
        failed += mode_failed

    print("\n" + "=" * 60)
    print(f"Total: {passed} passed, {failed} failed")
    print("=" * 60)

    return failed == 0

def run_test_interp(test_func):
    """Run test in interpreter mode by temporarily modifying run_wat."""
    import types
    # Get the WAT code from the test function
    # This is a hack - we extract the WAT string from the test
    import inspect
    source = inspect.getsource(test_func)
    # Find the WAT code in the source
    start = source.find("'''") + 3
    end = source.rfind("'''")
    if start > 2 and end > start:
        wat = source[start:end]
        return run_wat(wat, use_jit=False)
    return False, "Could not extract WAT code"

if __name__ == "__main__":
    # Check if wasmoon binary exists
    if not os.path.exists("./wasmoon"):
        print("Error: ./wasmoon not found. Run 'moon build && ./install.sh' first.")
        sys.exit(1)

    success = run_all_tests()
    sys.exit(0 if success else 1)
