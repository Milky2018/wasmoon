#!/usr/bin/env python3
"""Detect commits that require the full MachV closing evidence matrix."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


ISSUE_PATH = re.compile(r"^issues/ISS-(\d{3,})\.md$")
STATUS_LINE = re.compile(r"^- Status: ([a-z_]+)$", re.MULTILINE)
GATE_PATHS = {
    ".github/workflows/check.yml",
    ".github/workflows/perf.yml",
    "scripts/assert_target_identity.py",
    "scripts/check_committed_diff.py",
    "scripts/cutover_gate_manifest.py",
    "scripts/detect_cutover_closing_change.py",
    "scripts/run_fixed_smith_gate.py",
    "scripts/run_machv_cutover_perf.py",
    "scripts/smith_diff/run.py",
    "scripts/tests/test_cutover_gate.py",
}


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", *args],
        cwd=repo,
        stderr=subprocess.STDOUT,
        text=True,
    )


def file_at(repo: Path, revision: str, path: str) -> str | None:
    try:
        return git(repo, "show", f"{revision}:{path}")
    except subprocess.CalledProcessError:
        return None


def issue_status(content: str | None) -> str | None:
    if content is None:
        return None
    matched = STATUS_LINE.search(content)
    return matched.group(1) if matched is not None else None


def requires_cutover(repo: Path, base: str, head: str) -> bool:
    changed = [
        path
        for path in git(repo, "diff", "--name-only", base, head).splitlines()
        if path
    ]
    for path in changed:
        if path in GATE_PATHS or path.startswith("docs/perf/machv-migration/"):
            return True
        matched = ISSUE_PATH.match(path)
        if matched is None or int(matched.group(1)) < 193:
            continue
        before = issue_status(file_at(repo, base, path))
        after = issue_status(file_at(repo, head, path))
        if before != "closed" and after == "closed":
            return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", required=True)
    args = parser.parse_args()
    try:
        return 0 if requires_cutover(Path.cwd(), args.base, args.head) else 1
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"cutover detection failed safe: {error}", file=sys.stderr)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
