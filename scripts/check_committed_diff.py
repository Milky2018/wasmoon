#!/usr/bin/env python3
"""Run git diff --check over the committed event range."""

from __future__ import annotations

import argparse
import os
import subprocess
from pathlib import Path


def is_commit(repo: Path, revision: str) -> bool:
    return subprocess.run(
        ["git", "cat-file", "-e", f"{revision}^{{commit}}"],
        cwd=repo,
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base")
    parser.add_argument("--head")
    args = parser.parse_args()
    repo = Path.cwd()
    head = args.head or os.environ.get("CUTOVER_HEAD_SHA") or "HEAD"
    if not is_commit(repo, head):
        raise SystemExit(f"invalid head commit: {head}")
    base = args.base or os.environ.get("CUTOVER_BASE_SHA") or f"{head}^"
    if not is_commit(repo, base):
        base = f"{head}^"
    return subprocess.run(
        ["git", "diff", "--check", base, head],
        cwd=repo,
        check=False,
    ).returncode


if __name__ == "__main__":
    raise SystemExit(main())
