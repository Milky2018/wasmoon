#!/usr/bin/env python3
"""
WASI Preview1 CLI integration smoke tests.

Runs a curated set of WAT modules under both JIT and interpreter modes via
`./wasmoon run` and checks output + exit status.
"""

import os
import subprocess
import sys
import tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WAT_DIR = SCRIPT_DIR


def run_wat_file(wat_file, use_jit=True, expected=None, extra_run_args=None, tmpdir=None):
    """Run a WAT file and check results."""
    wat_path = os.path.join(WAT_DIR, wat_file)

    try:
        # NOTE: wasmoon currently expects FILE before some options like --env.
        cmd = ["./wasmoon", "run", wat_path]
        if not use_jit:
            cmd.append("--no-jit")
        if extra_run_args:
            expanded = []
            for arg in extra_run_args:
                if tmpdir is not None:
                    expanded.append(arg.replace("{tmpdir}", tmpdir))
                else:
                    expanded.append(arg)
            cmd.extend(expanded)

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)

        if result.returncode != 0:
            return (
                False,
                f"Non-zero exit code {result.returncode}: {result.stderr or result.stdout}",
            )

        if expected is not None:
            if isinstance(expected, tuple):
                stream, needle = expected
                haystack = result.stdout if stream == "stdout" else result.stderr
                if needle not in haystack:
                    return (
                        False,
                        f"Expected {stream} to contain '{needle}', got stdout='{result.stdout}' stderr='{result.stderr}'",
                    )
            else:
                if expected not in result.stdout:
                    return False, f"Expected stdout to contain '{expected}', got '{result.stdout}'"

        return True, result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return False, "Timeout"
    except Exception as e:
        return False, str(e)


# Test definitions: (name, wat_file, expected, extra_run_args)
# expected=None means just check it runs without error (and exits 0)
TESTS = [
    # Basic I/O tests
    ("fd_write", "fd_write.wat", "Hello from fd_write!", None),
    ("fd_write (stderr)", "fd_write_stderr.wat", ("stderr", "Hello stderr!"), None),
    ("fd_write (multiple iovecs)", "fd_write_multiple_iovecs.wat", "Hello World!", None),
    # Clock tests
    ("clock_time_get", "clock_time_get.wat", "clock_time_get: OK", None),
    ("clock_time_get (monotonic)", "clock_time_get_monotonic.wat", "clock monotonic: OK", None),
    ("clock_time_get (invalid)", "clock_time_get_invalid.wat", "clock invalid: OK", None),
    ("clock_res_get", "clock_res_get.wat", "clock_res_get: OK", None),
    ("clock_res_get (invalid)", "clock_res_get_invalid.wat", "clock_res invalid: OK", None),
    # Random
    ("random_get", "random_get.wat", "random_get: OK", None),
    # Args and environ
    ("args_sizes_get", "args_sizes_get.wat", "args_sizes_get: OK", None),
    ("args_get", "args_get.wat", "args_get: OK", None),
    (
        "environ_sizes_get",
        "environ_sizes_get.wat",
        "environ_sizes_get: OK",
        ["--env", "WASMOON_TEST=1"],
    ),
    (
        "environ_get",
        "environ_get.wat",
        "environ_get: OK",
        ["--env", "WASMOON_TEST=1"],
    ),
    # File descriptor operations
    ("fd_fdstat_get", "fd_fdstat_get.wat", "fd_fdstat_get: OK", None),
    ("fd_filestat_get", "fd_filestat_get.wat", "fd_filestat_get: OK", None),
    ("fd_fdstat_set_rights", "fd_fdstat_set_rights.wat", "fd_fdstat_set_rights: OK", None),
    ("fd_fdstat_set_flags", "fd_fdstat_set_flags.wat", "fd_fdstat_set_flags: OK", None),
    # Seek and tell
    ("fd_seek (stdout fails)", "fd_seek_stdout_fails.wat", "fd_seek stdout: OK", None),
    ("fd_tell (stdout fails)", "fd_tell_stdout_fails.wat", "fd_tell stdout: OK", None),
    ("fd_seek (invalid)", "fd_seek_invalid.wat", "fd_seek invalid: OK", None),
    # pread/pwrite
    ("fd_pread (invalid)", "fd_pread_invalid.wat", "fd_pread invalid: OK", None),
    ("fd_pwrite (invalid)", "fd_pwrite_invalid.wat", "fd_pwrite invalid: OK", None),
    ("fd_pread (stdin fails)", "fd_pread_stdin_fails.wat", "fd_pread stdin: OK", None),
    ("fd_pwrite (stdout fails)", "fd_pwrite_stdout_fails.wat", "fd_pwrite stdout: OK", None),
    # Sync
    ("fd_sync", "fd_sync.wat", "fd_sync: OK", None),
    ("fd_datasync", "fd_datasync.wat", "fd_datasync: OK", None),
    ("fd_advise", "fd_advise.wat", "fd_advise: OK", None),
    # Scheduler
    ("sched_yield", "sched_yield.wat", "sched_yield: OK", None),
    # Poll
    ("poll_oneoff (clock)", "poll_oneoff_clock.wat", "poll_oneoff: OK", None),
    ("poll_oneoff (zero)", "poll_oneoff_zero.wat", "poll_oneoff zero: OK", None),
    # Real filesystem I/O (requires --dir)
    (
        "path_open + fd_write/fd_read",
        "path_open_create_write_read.wat",
        "path_open create/read: OK",
        ["--dir", "{tmpdir}::/sandbox"],
    ),
    (
        "fd_pwrite/fd_pread on file",
        "fd_pwrite_pread_file.wat",
        "fd_pwrite/pread: OK",
        ["--dir", "{tmpdir}::/sandbox"],
    ),
    # Directory
    ("fd_readdir (invalid)", "fd_readdir_invalid.wat", "fd_readdir invalid: OK", None),
    ("path_open (invalid)", "path_open_invalid.wat", "path_open invalid: OK", None),
    # File metadata
    (
        "fd_filestat_set_size (invalid)",
        "fd_filestat_set_size_invalid.wat",
        "fd_filestat_set_size: OK",
        None,
    ),
    (
        "fd_filestat_set_times (invalid)",
        "fd_filestat_set_times_invalid.wat",
        "fd_filestat_set_times: OK",
        None,
    ),
    ("fd_allocate (invalid)", "fd_allocate_invalid.wat", "fd_allocate: OK", None),
    ("fd_renumber (invalid)", "fd_renumber_invalid.wat", "fd_renumber invalid: OK", None),
    # Error handling tests
    ("fd_close (invalid)", "fd_close_invalid.wat", "fd_close invalid: OK", None),
    ("fd_read (invalid)", "fd_read_invalid.wat", "fd_read invalid: OK", None),
    ("fd_prestat_get (invalid)", "fd_prestat_get_invalid.wat", "fd_prestat_get invalid: OK", None),
    # Socket tests
    ("sock_accept (invalid)", "sock_accept_invalid.wat", "sock_accept invalid: OK", None),
    ("sock_recv (invalid)", "sock_recv_invalid.wat", "sock_recv invalid: OK", None),
    ("sock_send (invalid)", "sock_send_invalid.wat", "sock_send invalid: OK", None),
    ("sock_shutdown (invalid)", "sock_shutdown_invalid.wat", "sock_shutdown invalid: OK", None),
]


def run_all_tests():
    """Run all tests and report results."""
    passed = 0
    failed = 0

    print("=" * 60)
    print("WASI Preview1 Test Suite")
    print("=" * 60)

    for mode in ["JIT", "Interpreter"]:
        use_jit = mode == "JIT"
        print(f"\n--- {mode} Mode ---\n")

        mode_passed = 0
        mode_failed = 0
        with tempfile.TemporaryDirectory(prefix="wasmoon_wasip1_") as tmpdir:
            for name, wat_file, expected, extra_run_args in TESTS:
                success, msg = run_wat_file(
                    wat_file,
                    use_jit=use_jit,
                    expected=expected,
                    extra_run_args=extra_run_args,
                    tmpdir=tmpdir,
                )

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
    if not os.path.exists("./wasmoon"):
        print("Error: ./wasmoon not found. Run 'moon build && ./install.sh' first.")
        sys.exit(1)

    success = run_all_tests()
    sys.exit(0 if success else 1)
