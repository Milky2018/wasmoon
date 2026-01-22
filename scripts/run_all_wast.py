#!/usr/bin/env python3
"""Run all .wast tests and report results for both JIT and interpreter modes."""

import argparse
import subprocess
import sys
from pathlib import Path


def run_test(wast_file: Path, use_jit: bool) -> tuple[int | None, int | None, str | None]:
    """Run a single wast test and return (passed, failed, error)."""
    cmd = ["./wasmoon", "test", str(wast_file)]
    if not use_jit:
        cmd.append("--no-jit")

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10,
        )
        output = result.stdout + result.stderr

        # Check for crash (non-zero exit code without proper output)
        if result.returncode != 0 and "Passed:" not in output:
            last_line = ""
            for line in output.split("\n"):
                if line.strip():
                    last_line = line.strip()
            if last_line:
                return None, None, f"Crash (exit {result.returncode}): {last_line}"
            return None, None, f"Crash (exit {result.returncode})"

        if "Error" in output and "Passed:" not in output:
            # Parse error
            for line in output.split("\n"):
                if "Error" in line:
                    return None, None, line.strip()
            return None, None, "Unknown error"

        # Parse results
        passed = failed = 0
        for line in output.split("\n"):
            if "Passed:" in line:
                passed = int(line.split(":")[1].strip())
            elif "Failed:" in line:
                failed = int(line.split(":")[1].strip())

        return passed, failed, None
    except subprocess.TimeoutExpired:
        return None, None, "Timeout"
    except Exception as e:
        return None, None, str(e)


def run_tests_for_mode(wast_files: list[Path], test_dir: Path, use_jit: bool) -> dict:
    """Run all tests for a specific mode and return results."""
    mode_name = "JIT" if use_jit else "Interpreter"
    print(f"\n{'='*60}")
    print(f"Running {len(wast_files)} tests with {mode_name} mode...")
    print("="*60 + "\n")

    total_passed = 0
    total_failed = 0
    fully_passed: list[str] = []
    has_failures: list[tuple[str, int, int]] = []
    has_errors: list[str] = []

    for wast_file in wast_files:
        name = str(wast_file.relative_to(test_dir))
        passed, failed, error = run_test(wast_file, use_jit)

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
    args = parser.parse_args()

    # Validate mutually exclusive options
    if args.only_jit and args.only_interp:
        parser.error("--only-jit and --only-interp are mutually exclusive")

    test_dir = Path(args.dir)
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

    print(f"Found {len(wast_files)} .wast test files in '{test_dir}'")

    interp_results = None
    jit_results = None

    # Run tests based on mode selection
    if not args.only_jit:
        # Run tests with interpreter (--no-jit)
        interp_results = run_tests_for_mode(wast_files, test_dir, use_jit=False)

    if not args.only_interp:
        # Run tests with JIT
        jit_results = run_tests_for_mode(wast_files, test_dir, use_jit=True)

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
