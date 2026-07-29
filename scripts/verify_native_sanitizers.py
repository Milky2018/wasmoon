#!/usr/bin/env python3
"""Verify that native CI executables contain ASan and UBSan instrumentation."""

from __future__ import annotations

import argparse
import platform
import subprocess
from pathlib import Path


def command_output(command: list[str]) -> str:
    result = subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"{' '.join(command)} failed: {detail}")
    return result.stdout


def missing_sanitizers(dependencies: str, symbols: str) -> list[str]:
    dependency_text = dependencies.lower()
    missing = []
    if "asan" not in dependency_text and "__asan_" not in symbols:
        missing.append("ASan")
    if "ubsan" not in dependency_text and "__ubsan_handle_" not in symbols:
        missing.append("UBSan")
    return missing


def inspect_binary(path: Path) -> list[str]:
    system = platform.system()
    if system == "Darwin":
        dependencies = command_output(["otool", "-L", str(path)])
    elif system == "Linux":
        dependencies = command_output(["ldd", str(path)])
    else:
        raise RuntimeError(f"unsupported host for sanitizer verification: {system}")
    symbols = command_output(["nm", "-a", str(path)])
    return missing_sanitizers(dependencies, symbols)


def collect_binaries(target_dir: Path) -> tuple[list[Path], list[Path]]:
    release_root = target_dir / "native/release/build"
    test_root = target_dir / "native/debug/test"
    cli = sorted(
        path
        for path in release_root.rglob("wasmoon.exe")
        if "/cmd/wasmoon/" in path.as_posix()
        and ".dSYM/" not in path.as_posix()
    )
    tests = sorted(
        path
        for path in test_root.rglob("*.exe")
        if ".dSYM/" not in path.as_posix()
    )
    return cli, tests


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-dir", type=Path, required=True)
    parser.add_argument("--minimum-test-binaries", type=int, default=1)
    args = parser.parse_args()

    cli, tests = collect_binaries(args.target_dir)
    if len(cli) != 1:
        print(f"expected one sanitizer CLI executable, found {len(cli)}")
        return 1
    if len(tests) < args.minimum_test_binaries:
        print(
            "expected at least "
            f"{args.minimum_test_binaries} sanitizer test executables, "
            f"found {len(tests)}"
        )
        return 1

    failures = []
    for path in cli + tests:
        missing = inspect_binary(path)
        if missing:
            failures.append(f"{path}: missing {', '.join(missing)}")
    if failures:
        print("\n".join(failures))
        return 1

    print(
        "verified ASan and UBSan instrumentation in "
        f"{len(cli)} CLI and {len(tests)} test executables"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
