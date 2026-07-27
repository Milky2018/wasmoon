#!/usr/bin/env python3
"""Check the exact upstream Component Model snapshot and suite partition."""

from __future__ import annotations

import sys
from pathlib import Path

from component_snapshot import SnapshotError, validate_snapshot


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    try:
        snapshot = validate_snapshot(repo_root)
    except SnapshotError as error:
        print(f"Component snapshot check failed: {error}", file=sys.stderr)
        return 1

    print(
        "Component snapshot verified: "
        f"{snapshot.repository}@{snapshot.commit} "
        f"(tree {snapshot.upstream_tree})"
    )
    for name, files in snapshot.suites.items():
        print(f"  {name}: {len(files)} .wast files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
