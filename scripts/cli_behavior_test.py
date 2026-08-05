#!/usr/bin/env python3
"""Black-box checks of the wasmoon CLI's public behaviour.

These run the built binary. Everything here is something a user or a script
can observe -- an exit status, what lands on stdout, what lands on stderr --
so nothing in this file reads the source.

That distinction is the point. `scripts/tests/test_cli_version.py` pins the
version constant against the manifest by reading both, which catches drift at
commit time before anything is built, but it cannot tell whether `--version`
runs at all. This can, and is the authority when the two disagree.

Needs `./wasmoon` in the repo root: run `moon build && ./install.sh` first.
CI runs this as its own step after the build.
"""

from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WASMOON = ROOT / "wasmoon"
MANIFEST = ROOT / "modules/wasmoon/moon.mod"

PASSING_WAST = """(module (func (export "one") (result i32) (i32.const 1)))
(assert_return (invoke "one") (i32.const 1))
"""

# Asserts 2 against a function that returns 1, so the runner reports one
# failed assertion and nothing else goes wrong.
FAILING_WAST = """(module (func (export "one") (result i32) (i32.const 1)))
(assert_return (invoke "one") (i32.const 2))
"""

# Truncated mid-module: the parser rejects it before any assertion runs.
UNPARSEABLE_WAST = """(module (func (export "x")
"""


class Failure(Exception):
    pass


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [str(WASMOON), *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=120,
    )


def manifest_version() -> str:
    match = re.search(
        r'^\s*version\s*=\s*"([^"]+)"', MANIFEST.read_text(), re.MULTILINE
    )
    if match is None:
        raise Failure(f"no version field in {MANIFEST}")
    return match.group(1)


def expect(label: str, condition: bool, detail: str) -> None:
    if not condition:
        raise Failure(f"{label}: {detail}")
    print(f"  ok  {label}")


def check_version_flags() -> None:
    expected = manifest_version()
    for flag in ("--version", "-V"):
        proc = run(flag)
        expect(
            f"`wasmoon {flag}` exits 0",
            proc.returncode == 0,
            f"exit {proc.returncode}, stderr={proc.stderr.strip()!r}",
        )
        expect(
            f"`wasmoon {flag}` prints the manifest version to stdout",
            proc.stdout.strip() == expected,
            f"stdout={proc.stdout.strip()!r}, manifest={expected!r}",
        )
        # A version was asked for, so it is output, not a diagnostic.
        expect(
            f"`wasmoon {flag}` writes nothing to stderr",
            proc.stderr == "",
            f"stderr={proc.stderr!r}",
        )


def check_test_exit_codes(tmp: Path) -> None:
    passing = tmp / "passing.wast"
    passing.write_text(PASSING_WAST)
    failing = tmp / "failing.wast"
    failing.write_text(FAILING_WAST)
    unparseable = tmp / "unparseable.wast"
    unparseable.write_text(UNPARSEABLE_WAST)

    proc = run("test", str(passing))
    expect(
        "`wasmoon test` exits 0 when every assertion passes",
        proc.returncode == 0,
        f"exit {proc.returncode}",
    )
    expect(
        "a passing run still reports its tally",
        "Passed:  1" in proc.stdout and "Failed:  0" in proc.stdout,
        f"stdout={proc.stdout!r}",
    )

    proc = run("test", str(failing))
    # The whole point of ISS-387: a failure the exit status carries, so
    # `set -e` and `&&` chains see it without parsing the report.
    expect(
        "`wasmoon test` exits non-zero when an assertion fails",
        proc.returncode != 0,
        "exit 0 on a failing assertion",
    )
    expect(
        "a failing run still reports its tally",
        "Failed:  1" in proc.stdout,
        f"stdout={proc.stdout!r}",
    )

    proc = run("test", str(unparseable))
    expect(
        "`wasmoon test` exits non-zero on an unparseable script",
        proc.returncode != 0,
        "exit 0 on an unparseable script",
    )
    expect(
        "a parse failure reports no tally",
        "Passed:" not in proc.stdout,
        f"stdout={proc.stdout!r}",
    )

    proc = run("test")
    expect(
        "`wasmoon test` with no file exits 2 for usage",
        proc.returncode == 2,
        f"exit {proc.returncode}",
    )
    expect(
        "a usage error writes nothing to stdout",
        proc.stdout == "",
        f"stdout={proc.stdout!r}",
    )


def main() -> int:
    if not WASMOON.exists():
        print(
            f"{WASMOON} not found -- run `moon build && ./install.sh` first",
            file=sys.stderr,
        )
        return 2
    print("CLI behaviour checks")
    try:
        with tempfile.TemporaryDirectory() as directory:
            check_version_flags()
            check_test_exit_codes(Path(directory))
    except Failure as failure:
        print(f"FAILED {failure}", file=sys.stderr)
        return 1
    print("all CLI behaviour checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
