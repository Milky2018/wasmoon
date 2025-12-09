#!/usr/bin/env python3
"""Run all .wast tests and report results for both JIT and interpreter modes."""

import subprocess
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
            timeout=60,
        )
        output = result.stdout + result.stderr

        # Check for crash (non-zero exit code without proper output)
        if result.returncode != 0 and "Passed:" not in output:
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


def run_tests_for_mode(wast_files: list[Path], use_jit: bool) -> dict:
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
        name = wast_file.name
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

        print(f"{name:40} {status}")

    return {
        "mode": mode_name,
        "total_passed": total_passed,
        "total_failed": total_failed,
        "fully_passed": fully_passed,
        "has_failures": has_failures,
        "has_errors": has_errors,
        "total_files": len(wast_files),
    }


def print_summary(results: dict) -> None:
    """Print summary for a mode."""
    mode = results["mode"]
    print(f"\n{mode} Mode Summary:")
    print("-" * 40)
    print(f"  Files fully passed:  {len(results['fully_passed'])}/{results['total_files']}")
    print(f"  Files with failures: {len(results['has_failures'])}")
    print(f"  Files with errors:   {len(results['has_errors'])}")
    print(f"  Total tests passed:  {results['total_passed']}")
    print(f"  Total tests failed:  {results['total_failed']}")

    if results['has_errors']:
        print(f"\n  [ERROR] ({len(results['has_errors'])}):")
        for name in results['has_errors'][:10]:
            print(f"    - {name}")
        if len(results['has_errors']) > 10:
            print(f"    ... and {len(results['has_errors']) - 10} more")


def main() -> None:
    test_dir = Path("testsuite/data")
    wast_files = sorted(test_dir.glob("*.wast"))

    print(f"Found {len(wast_files)} .wast test files")

    # Run tests with interpreter (--no-jit)
    interp_results = run_tests_for_mode(wast_files, use_jit=False)

    # Run tests with JIT
    jit_results = run_tests_for_mode(wast_files, use_jit=True)

    # Print combined summary
    print("\n" + "=" * 60)
    print("COMBINED SUMMARY")
    print("=" * 60)

    print_summary(interp_results)
    print_summary(jit_results)

    # Compare results
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


if __name__ == "__main__":
    main()
