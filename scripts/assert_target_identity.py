#!/usr/bin/env python3
"""Reject a CI runner whose real architecture does not match a named target."""

from __future__ import annotations

import argparse
import json
import platform
import subprocess
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", choices=["darwin-arm64", "linux-amd64"])
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
    target = next(
        (item for item in baseline["targets"] if item["name"] == args.target),
        None,
    )
    if target is None:
        raise SystemExit(f"target {args.target!r} is absent from {args.baseline}")

    uname_machine = subprocess.check_output(["uname", "-m"], text=True).strip()
    identity = {
        "schema_version": 1,
        "target": args.target,
        "system": platform.system(),
        "machine": platform.machine(),
        "uname_m": uname_machine,
        "processor": platform.processor(),
        "required_uname_m": target["required_uname_m"],
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(identity, indent=2) + "\n", encoding="utf-8")

    expected_system = "Darwin" if args.target == "darwin-arm64" else "Linux"
    if identity["system"] != expected_system:
        raise SystemExit(
            f"target {args.target} requires {expected_system}, got {identity['system']}"
        )
    if uname_machine not in target["required_uname_m"]:
        raise SystemExit(
            f"target {args.target} requires uname -m in "
            f"{target['required_uname_m']}, got {uname_machine!r}"
        )
    print(json.dumps(identity, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
