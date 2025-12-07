#!/usr/bin/env python3
"""Run all .wast tests and report results."""

import subprocess
import os
import sys
from pathlib import Path

def run_test(wast_file):
    """Run a single wast test and return (passed, failed, error)."""
    try:
        result = subprocess.run(
            ["./wasmoon", "wast", str(wast_file)],
            capture_output=True,
            text=True,
            timeout=60
        )
        output = result.stdout + result.stderr

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

def main():
    test_dir = Path("testsuite/data")
    wast_files = sorted(test_dir.glob("*.wast"))

    print(f"Running {len(wast_files)} .wast tests...\n")

    results = []
    total_passed = total_failed = total_errors = 0
    fully_passed = []
    has_failures = []
    has_errors = []

    for wast_file in wast_files:
        name = wast_file.name
        passed, failed, error = run_test(wast_file)

        if error:
            status = f"ERROR: {error[:60]}"
            total_errors += 1
            has_errors.append(name)
        elif failed == 0:
            status = f"✅ PASS ({passed} tests)"
            total_passed += passed
            fully_passed.append(name)
        else:
            status = f"❌ {passed}/{passed+failed} ({failed} failures)"
            total_passed += passed
            total_failed += failed
            has_failures.append((name, passed, failed))

        print(f"{name:40} {status}")

    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)
    print(f"Files fully passed:  {len(fully_passed)}/{len(wast_files)}")
    print(f"Files with failures: {len(has_failures)}")
    print(f"Files with errors:   {len(has_errors)}")
    print(f"\nTotal tests passed:  {total_passed}")
    print(f"Total tests failed:  {total_failed}")

    if fully_passed:
        print(f"\n✅ Fully passed ({len(fully_passed)}):")
        for name in fully_passed:
            print(f"  - {name}")

    if has_failures:
        print(f"\n❌ Has failures ({len(has_failures)}):")
        for name, p, f in sorted(has_failures, key=lambda x: -x[2]):
            print(f"  - {name}: {f} failures")

    if has_errors:
        print(f"\n⚠️  Errors ({len(has_errors)}):")
        for name in has_errors:
            print(f"  - {name}")

if __name__ == "__main__":
    main()
