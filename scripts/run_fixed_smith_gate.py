#!/usr/bin/env python3
"""Validate and execute the versioned Wasm-Smith cutover corpus."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("docs/perf/machv-migration/smith.json"),
    )
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    config = Path(manifest["config"])
    actual = sha256(config)
    if actual != manifest["config_sha256"]:
        raise SystemExit(
            f"Wasm-Smith config checksum mismatch: expected "
            f"{manifest['config_sha256']}, got {actual}"
        )
    command = [
        sys.executable,
        "scripts/smith_diff/run.py",
        "run",
        "--seed",
        str(manifest["seed"]),
        "--count",
        str(manifest["count"]),
        "--seed-size",
        str(manifest["seed_size"]),
        "--timeout",
        str(manifest["timeout_seconds"]),
        "--config",
        str(config),
        "--no-shrink",
        "--out",
        str(args.out),
    ]
    return subprocess.run(command, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
