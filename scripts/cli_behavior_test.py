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

# Modules the validator must reject. Each names a type index of the wrong
# kind, or one that does not exist. These used to abort the process from
# inside the validator -- SIGABRT, the diagnostic on stdout, and for the
# out-of-range case nothing on either stream (ISS-395). A crash is not an
# exit code, so none of the guarantees below applied to them.
INVALID_MODULES = {
    "struct.get on a func type": """(module
  (type $f (func))
  (func (export "go") (result i32)
    (struct.get $f 0 (ref.null none))))
""",
    "array.get on a func type": """(module
  (type $f (func))
  (func (export "go") (result i32)
    (array.get $f (ref.null none) (i32.const 0))))
""",
    "type index out of range": """(module
  (type $f (func))
  (func (export "go") (result i32)
    (struct.get 99 0 (ref.null none))))
""",
}

# A `(type $t)` on a function where `$t` names a struct. This one aborted
# during *parsing*, upstream of validation, so it took down every command in
# both binaries -- validating harder could never have caught it (ISS-396).
# Kept separate from the modules above because what it pins is the breadth:
# each subcommand parses, so each has to survive it.
UNPARSEABLE_TYPE_KIND = """(module
  (type $s (struct (field i32)))
  (func (export "go") (type $s)))
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


def check_invalid_modules(tmp: Path) -> None:
    for label, source in INVALID_MODULES.items():
        path = tmp / (label.replace(" ", "_").replace(".", "_") + ".wat")
        path.write_text(source)
        proc = run("run", str(path), "--invoke", "go")
        # A signal is reported as a negative returncode by subprocess, and is
        # the specific failure this covers: the validator killing the process
        # rather than rejecting the module.
        expect(
            f"`run` on {label} is rejected, not fatal",
            proc.returncode > 0,
            f"exit {proc.returncode}"
            + (" (killed by signal)" if proc.returncode < 0 else ""),
        )
        expect(
            f"`run` on {label} writes its diagnostic to stderr",
            proc.stdout == "" and proc.stderr != "",
            f"stdout={proc.stdout!r}, stderr={proc.stderr!r}",
        )
        # These parse and then fail validation, which is a later exit than the
        # cases below and was reached by a different path: `explore` printed
        # the error to stdout and returned 0, so it reported success for a
        # module it had just rejected.
        proc = run("explore", str(path))
        expect(
            f"`explore` on {label} exits non-zero",
            proc.returncode > 0,
            f"exit {proc.returncode}"
            + (" (killed by signal)" if proc.returncode < 0 else ""),
        )
        expect(
            f"`explore` on {label} writes its diagnostic to stderr",
            proc.stdout == "" and proc.stderr != "",
            f"stdout={proc.stdout!r}, stderr={proc.stderr!r}",
        )


def check_malformed_type_kind_across_commands(tmp: Path) -> None:
    wat = tmp / "bad_type_kind.wat"
    wat.write_text(UNPARSEABLE_TYPE_KIND)
    wast = tmp / "bad_type_kind.wast"
    wast.write_text(UNPARSEABLE_TYPE_KIND)
    for command in (
        ["run", str(wat), "--invoke", "go"],
        ["run", str(wat), "--invoke", "go", "--no-jit"],
        ["disasm", str(wat)],
        ["explore", str(wat)],
        ["test", str(wast)],
    ):
        proc = run(*command)
        expect(
            f"`{command[0]}` survives a struct type in a func position"
            + (" (--no-jit)" if "--no-jit" in command else ""),
            proc.returncode > 0,
            f"exit {proc.returncode}"
            + (" (killed by signal)" if proc.returncode < 0 else ""),
        )
        expect(
            f"`{command[0]}` reports it on stderr"
            + (" (--no-jit)" if "--no-jit" in command else ""),
            proc.stdout == "" and proc.stderr != "",
            f"stdout={proc.stdout!r}, stderr={proc.stderr!r}",
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
            check_invalid_modules(Path(directory))
            check_malformed_type_kind_across_commands(Path(directory))
    except Failure as failure:
        print(f"FAILED {failure}", file=sys.stderr)
        return 1
    print("all CLI behaviour checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
