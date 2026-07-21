#!/usr/bin/env python3
"""Reject a CI runner whose real architecture does not match a named target."""

from __future__ import annotations

import argparse
import json
import platform
import subprocess
from pathlib import Path


TARGETS = {
    "darwin-arm64": {"system": "Darwin", "uname_m": ["arm64", "aarch64"]},
    "linux-amd64": {"system": "Linux", "uname_m": ["x86_64"]},
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", choices=TARGETS)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    target = TARGETS[args.target]

    uname_machine = subprocess.check_output(["uname", "-m"], text=True).strip()
    identity = {
        "schema_version": 1,
        "target": args.target,
        "system": platform.system(),
        "machine": platform.machine(),
        "uname_m": uname_machine,
        "processor": platform.processor(),
        "required_uname_m": target["uname_m"],
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(identity, indent=2) + "\n", encoding="utf-8")

    if identity["system"] != target["system"]:
        raise SystemExit(
            f"target {args.target} requires {target['system']}, got {identity['system']}"
        )
    if uname_machine not in target["uname_m"]:
        raise SystemExit(
            f"target {args.target} requires uname -m in "
            f"{target['uname_m']}, got {uname_machine!r}"
        )
    print(json.dumps(identity, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
