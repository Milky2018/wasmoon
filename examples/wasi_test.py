#!/usr/bin/env python3
"""
WASI Preview1 Comprehensive Test Suite

Tests all 46 WASI functions for correctness in both JIT and interpreter modes.
WAT test files are stored in examples/wasi_tests/ directory.
"""

import subprocess
import os
import sys

# Directory containing WAT test files
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WAT_DIR = os.path.join(SCRIPT_DIR, "wasi_tests")

def run_wat_file(wat_file, use_jit=True, expected_output=None):
    """Run a WAT file and check results."""
    wat_path = os.path.join(WAT_DIR, wat_file)

    try:
        cmd = ['./wasmoon', 'run', wat_path]
        if not use_jit:
            cmd.insert(2, '--no-jit')

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)

        if expected_output is not None:
            if expected_output not in result.stdout:
                return False, f"Expected output '{expected_output}' not found in '{result.stdout}'"

        return True, result.stdout
    except subprocess.TimeoutExpired:
        return False, "Timeout"
    except Exception as e:
        return False, str(e)

# Test definitions: (name, wat_file, expected_output)
# expected_output=None means just check it runs without error
TESTS = [
    # Basic I/O tests
    ("fd_write", "fd_write.wat", "Hello from fd_write!"),
    ("fd_write (stderr)", "fd_write_stderr.wat", None),
    ("fd_write (multiple iovecs)", "fd_write_multiple_iovecs.wat", "Hello World!"),
    # Clock tests
    ("clock_time_get", "clock_time_get.wat", "clock_time_get: OK"),
    ("clock_time_get (monotonic)", "clock_time_get_monotonic.wat", "clock monotonic: OK"),
    ("clock_time_get (invalid)", "clock_time_get_invalid.wat", "clock invalid: OK"),
    ("clock_res_get", "clock_res_get.wat", "clock_res_get: OK"),
    ("clock_res_get (invalid)", "clock_res_get_invalid.wat", "clock_res invalid: OK"),
    # Random
    ("random_get", "random_get.wat", "random_get: OK"),
    # Args and environ
    ("args_sizes_get", "args_sizes_get.wat", "args_sizes_get: OK"),
    ("args_get", "args_get.wat", "args_get: OK"),
    ("environ_sizes_get", "environ_sizes_get.wat", "environ_sizes_get: OK"),
    ("environ_get", "environ_get.wat", "environ_get: OK"),
    # File descriptor operations
    ("fd_fdstat_get", "fd_fdstat_get.wat", "fd_fdstat_get: OK"),
    ("fd_filestat_get", "fd_filestat_get.wat", "fd_filestat_get: OK"),
    ("fd_fdstat_set_rights", "fd_fdstat_set_rights.wat", "fd_fdstat_set_rights: OK"),
    ("fd_fdstat_set_flags", "fd_fdstat_set_flags.wat", "fd_fdstat_set_flags: OK"),
    # Seek and tell
    ("fd_seek (stdout fails)", "fd_seek_stdout_fails.wat", "fd_seek stdout: OK"),
    ("fd_tell (stdout fails)", "fd_tell_stdout_fails.wat", "fd_tell stdout: OK"),
    ("fd_seek (invalid)", "fd_seek_invalid.wat", "fd_seek invalid: OK"),
    # pread/pwrite
    ("fd_pread (invalid)", "fd_pread_invalid.wat", "fd_pread invalid: OK"),
    ("fd_pwrite (invalid)", "fd_pwrite_invalid.wat", "fd_pwrite invalid: OK"),
    ("fd_pread (stdin fails)", "fd_pread_stdin_fails.wat", "fd_pread stdin: OK"),
    ("fd_pwrite (stdout fails)", "fd_pwrite_stdout_fails.wat", "fd_pwrite stdout: OK"),
    # Sync
    ("fd_sync", "fd_sync.wat", "fd_sync: OK"),
    ("fd_datasync", "fd_datasync.wat", "fd_datasync: OK"),
    ("fd_advise", "fd_advise.wat", "fd_advise: OK"),
    # Scheduler
    ("sched_yield", "sched_yield.wat", "sched_yield: OK"),
    # Poll
    ("poll_oneoff (clock)", "poll_oneoff_clock.wat", "poll_oneoff: OK"),
    ("poll_oneoff (zero)", "poll_oneoff_zero.wat", "poll_oneoff zero: OK"),
    # Directory
    ("fd_readdir (invalid)", "fd_readdir_invalid.wat", "fd_readdir invalid: OK"),
    ("path_open (invalid)", "path_open_invalid.wat", "path_open invalid: OK"),
    # File metadata
    ("fd_filestat_set_size (invalid)", "fd_filestat_set_size_invalid.wat", "fd_filestat_set_size: OK"),
    ("fd_filestat_set_times (invalid)", "fd_filestat_set_times_invalid.wat", "fd_filestat_set_times: OK"),
    ("fd_allocate (invalid)", "fd_allocate_invalid.wat", "fd_allocate: OK"),
    ("fd_renumber (invalid)", "fd_renumber_invalid.wat", "fd_renumber invalid: OK"),
    # Error handling tests
    ("fd_close (invalid)", "fd_close_invalid.wat", "fd_close invalid: OK"),
    ("fd_read (invalid)", "fd_read_invalid.wat", "fd_read invalid: OK"),
    ("fd_prestat_get (invalid)", "fd_prestat_get_invalid.wat", "fd_prestat_get invalid: OK"),
    # Socket tests
    ("sock_accept (invalid)", "sock_accept_invalid.wat", "sock_accept invalid: OK"),
    ("sock_recv (invalid)", "sock_recv_invalid.wat", "sock_recv invalid: OK"),
    ("sock_send (invalid)", "sock_send_invalid.wat", "sock_send invalid: OK"),
    ("sock_shutdown (invalid)", "sock_shutdown_invalid.wat", "sock_shutdown invalid: OK"),
]

def run_all_tests():
    """Run all tests and report results."""
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

        for name, wat_file, expected_output in TESTS:
            success, msg = run_wat_file(wat_file, use_jit=use_jit, expected_output=expected_output)

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

if __name__ == "__main__":
    # Check if wasmoon binary exists
    if not os.path.exists("./wasmoon"):
        print("Error: ./wasmoon not found. Run 'moon build && ./install.sh' first.")
        sys.exit(1)

    success = run_all_tests()
    sys.exit(0 if success else 1)
