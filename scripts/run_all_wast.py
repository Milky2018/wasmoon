#!/usr/bin/env python3
"""Run all .wast tests and report results for both JIT and interpreter modes."""

import argparse
import os
import signal
import subprocess
import sys
from pathlib import Path
from typing import Optional, Tuple

DEFAULT_TEST_TIMEOUT_SECONDS = int(os.environ.get("WASMOON_WAST_TIMEOUT", "20"))


def run_test(
    repo_root: Path,
    wasmoon_bin: Path,
    wast_file: Path,
    use_jit: bool,
    timeout_sec: int,
) -> Tuple[Optional[int], Optional[int], Optional[str]]:
    """Run a single wast test and return (passed, failed, error)."""
    cmd = [str(wasmoon_bin), "test", str(wast_file)]
    if not use_jit:
        cmd.append("--no-jit")

    try:
        proc = subprocess.Popen(
            cmd,
            cwd=repo_root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        try:
            stdout, stderr = proc.communicate(timeout=timeout_sec)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except OSError:
                pass
            try:
                proc.communicate(timeout=1)
            except subprocess.TimeoutExpired:
                # Keep moving even if the kernel keeps the process in
                # uninterruptible sleep for a while (possible under emulation).
                pass
            return None, None, f"Timeout ({timeout_sec}s)"

        output = (stdout or "") + (stderr or "")

        # The runner carries its verdict in the exit status; the Results
        # block carries the counts. A run that printed no Results block never
        # reached a verdict -- a crash, or a read/parse error that exited
        # before any assertion ran.
        if "Passed:" not in output:
            lines = [line.strip() for line in output.split("\n") if line.strip()]
            detail = next((l for l in lines if "Error" in l), None)
            if detail is None and lines:
                detail = " | ".join(lines[-3:])
            if detail:
                return None, None, f"Did not run (exit {proc.returncode}): {detail}"
            return None, None, f"Did not run (exit {proc.returncode})"

        # Parse results
        passed = failed = 0
        for line in output.split("\n"):
            if "Passed:" in line:
                passed = int(line.split(":")[1].strip())
            elif "Failed:" in line:
                failed = int(line.split(":")[1].strip())

        # Status and tally have to agree. A non-zero exit with nothing marked
        # failed means the run broke somewhere the tally does not cover, and
        # reporting it as a pass is how a real failure would slip through.
        if proc.returncode != 0 and failed == 0:
            return None, None, (
                f"Exited {proc.returncode} with no failed assertion"
            )

        return passed, failed, None
    except Exception as e:
        return None, None, str(e)


def detect_qemu_tcg() -> bool:
    cpuinfo = Path("/proc/cpuinfo")
    if not cpuinfo.exists():
        return False
    try:
        text = cpuinfo.read_text(encoding="utf-8", errors="ignore").lower()
    except OSError:
        return False
    return "qemu tcg" in text or "qemu virtual cpu" in text


def run_tests_for_mode(
    repo_root: Path,
    wasmoon_bin: Path,
    wast_files: list[Path],
    test_dir: Path,
    use_jit: bool,
    timeout_sec: int,
) -> dict:
    """Run all tests for a specific mode and return results."""
    mode_name = "JIT" if use_jit else "Interpreter"
    print(f"\n{'='*60}")
    print(f"Running {len(wast_files)} tests with {mode_name} mode (timeout={timeout_sec}s)...")
    print("="*60 + "\n")

    total_passed = 0
    total_failed = 0
    fully_passed: list[str] = []
    has_failures: list[tuple[str, int, int]] = []
    has_errors: list[str] = []

    for wast_file in wast_files:
        name = str(wast_file.relative_to(test_dir))
        passed, failed, error = run_test(
            repo_root,
            wasmoon_bin,
            wast_file,
            use_jit,
            timeout_sec,
        )

        if error or passed is None or failed is None:
            status = f"ERROR: {error[:50] if error else 'Unknown error'}"
            has_errors.append(name)
        elif failed == 0:
            status = f"[PASS] ({passed} tests)"
            total_passed += passed
            fully_passed.append(name)
        else:
            status = f"[FAIL] {passed}/{passed+failed} ({failed} failures)"
            total_passed += passed
            total_failed += failed
            has_failures.append((name, passed, failed))

        print(f"{name:50} {status}")

    return {
        "mode": mode_name,
        "total_passed": total_passed,
        "total_failed": total_failed,
        "fully_passed": fully_passed,
        "has_failures": has_failures,
        "has_errors": has_errors,
        "total_files": len(wast_files),
    }


def print_summary(results: dict, dump_failures: bool) -> None:
    """Print summary for a mode."""
    mode = results["mode"]
    print(f"\n{mode} Mode Summary:")
    print("-" * 40)
    print(f"  Files fully passed:  {len(results['fully_passed'])}/{results['total_files']}")
    print(f"  Files with failures: {len(results['has_failures'])}")
    print(f"  Files with errors:   {len(results['has_errors'])}")
    print(f"  Total tests passed:  {results['total_passed']}")
    print(f"  Total tests failed:  {results['total_failed']}")

    if results['has_errors'] and not dump_failures:
        print(f"\n  [ERROR] ({len(results['has_errors'])}):")
        for name in results['has_errors'][:10]:
            print(f"    - {name}")
        if len(results['has_errors']) > 10:
            print(f"    ... and {len(results['has_errors']) - 10} more")
    if dump_failures:
        if results['has_failures']:
            print(f"\n  [FAIL] ({len(results['has_failures'])}):")
            for name, _passed, _failed in results['has_failures']:
                print(f"    - {name}")
        if results['has_errors']:
            print(f"\n  [ERROR] ({len(results['has_errors'])}):")
            for name in results['has_errors']:
                print(f"    - {name}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Run .wast tests for wasmoon")
    parser.add_argument(
        "--dir",
        type=str,
        default="spec",
        help="Directory containing .wast files (default: spec)",
    )
    parser.add_argument(
        "--rec",
        action="store_true",
        help="Recursively search subdirectories for .wast files",
    )
    parser.add_argument(
        "--only-jit",
        action="store_true",
        help="Only run JIT mode tests",
    )
    parser.add_argument(
        "--only-interp",
        action="store_true",
        help="Only run interpreter mode tests (no JIT)",
    )
    parser.add_argument(
        "--dump-failures",
        action="store_true",
        help="Print full lists of failed/error files",
    )
    parser.add_argument(
        "--timeout-sec",
        type=int,
        default=None,
        help="Per-file timeout in seconds (default from WASMOON_WAST_TIMEOUT or 20)",
    )
    parser.add_argument(
        "--qemu-timeout-multiplier",
        type=float,
        default=4.0,
        help="Interpreter timeout multiplier for local QEMU TCG runs",
    )
    parser.add_argument(
        "--qemu-jit-timeout-multiplier",
        type=float,
        default=24.0,
        help="JIT timeout multiplier for local QEMU TCG runs",
    )
    parser.add_argument(
        "--no-qemu-relax",
        action="store_true",
        help="Disable automatic timeout multiplier on local QEMU TCG runs",
    )
    args = parser.parse_args()

    # Validate mutually exclusive options
    if args.only_jit and args.only_interp:
        parser.error("--only-jit and --only-interp are mutually exclusive")

    repo_root = Path(__file__).resolve().parent.parent
    wasmoon_bin = repo_root / "wasmoon"
    if not wasmoon_bin.exists():
        print(
            "Error: wasmoon binary not found. "
            "Run moon build --target native --release && ./install.sh first."
        )
        sys.exit(1)

    test_dir = repo_root / args.dir
    if not test_dir.exists():
        print(f"Error: Directory '{test_dir}' does not exist")
        return

    if args.rec:
        # Recursive: include all subdirectories
        wast_files = sorted(test_dir.glob("**/*.wast"))
    else:
        # Non-recursive: only direct children
        wast_files = sorted(test_dir.glob("*.wast"))

    if not wast_files:
        print(f"No .wast files found in '{test_dir}'")
        return

    base_timeout = (
        args.timeout_sec if args.timeout_sec is not None else DEFAULT_TEST_TIMEOUT_SECONDS
    )
    running_in_ci = os.getenv("CI", "").strip().lower() in {"1", "true", "yes"}
    running_on_qemu_tcg = detect_qemu_tcg()
    relax_timeout = (
        running_on_qemu_tcg
        and not running_in_ci
        and not args.no_qemu_relax
        and args.qemu_timeout_multiplier > 1.0
    )
    interp_multiplier = args.qemu_timeout_multiplier if relax_timeout else 1.0
    jit_multiplier = args.qemu_jit_timeout_multiplier if relax_timeout else 1.0
    interp_timeout_sec = int(max(1, round(base_timeout * interp_multiplier)))
    jit_timeout_sec = int(max(1, round(base_timeout * jit_multiplier)))

    print(f"Found {len(wast_files)} .wast test files in '{test_dir}'")
    print(
        "Timeout settings: "
        f"base={base_timeout}s, interp={interp_timeout_sec}s, jit={jit_timeout_sec}s, "
        f"qemu_tcg={running_on_qemu_tcg}, ci={running_in_ci}, relax={relax_timeout}"
    )

    interp_results = None
    jit_results = None

    # Run tests based on mode selection
    if not args.only_jit:
        # Run tests with interpreter (--no-jit)
        interp_results = run_tests_for_mode(
            repo_root,
            wasmoon_bin,
            wast_files,
            test_dir,
            use_jit=False,
            timeout_sec=interp_timeout_sec,
        )

    if not args.only_interp:
        # Run tests with JIT
        jit_results = run_tests_for_mode(
            repo_root,
            wasmoon_bin,
            wast_files,
            test_dir,
            use_jit=True,
            timeout_sec=jit_timeout_sec,
        )

    # Print combined summary
    print("\n" + "=" * 60)
    print("COMBINED SUMMARY")
    print("=" * 60)

    if interp_results:
        print_summary(interp_results, args.dump_failures)
    if jit_results:
        print_summary(jit_results, args.dump_failures)

    # Compare results (only if both modes were run)
    if interp_results and jit_results:
        print("\n" + "-" * 40)
        print("Comparison:")
        interp_ok = len(interp_results['fully_passed'])
        jit_ok = len(jit_results['fully_passed'])
        print(f"  Interpreter: {interp_ok}/{interp_results['total_files']} files passed")
        print(f"  JIT:         {jit_ok}/{jit_results['total_files']} files passed")

        # Show files that work with interpreter but fail with JIT
        interp_set = set(interp_results['fully_passed'])
        jit_set = set(jit_results['fully_passed'])
        jit_regressions = interp_set - jit_set
        if jit_regressions:
            print(f"\n  JIT regressions (pass with interpreter, fail with JIT): {len(jit_regressions)}")
            for name in sorted(jit_regressions)[:10]:
                print(f"    - {name}")
            if len(jit_regressions) > 10:
                print(f"    ... and {len(jit_regressions) - 10} more")

    # Exit with non-zero code if any tests failed or had errors
    total_failed = 0
    total_errors = 0
    if interp_results:
        total_failed += interp_results['total_failed']
        total_errors += len(interp_results['has_errors'])
    if jit_results:
        total_failed += jit_results['total_failed']
        total_errors += len(jit_results['has_errors'])

    if total_failed > 0 or total_errors > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
