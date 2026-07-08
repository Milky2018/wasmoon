#!/usr/bin/env python3
"""Audit reusable compiler-infrastructure module dependency boundaries."""

from pathlib import Path
import sys
from typing import Optional


ROOT = Path(__file__).resolve().parents[1]

REUSABLE_MODULES = [
    "modules/wasm_core",
    "modules/milkir",
    "modules/machv",
    "modules/regalloc",
    "modules/machv_regalloc",
    "modules/machv_emit",
    "modules/milkir_machv",
    "modules/aarch64_target",
    "modules/x64_target",
]

FORBIDDEN_IMPORT_PREFIXES = [
    "Milky2018/wasmoon",
    "Milky2018/wasmoon_jit",
    "Milky2018/machv_emit/jit_ffi",
]


def iter_package_manifests(module_dir: Path):
    yield from module_dir.rglob("moon.pkg")


def parse_imported_package(line: str) -> Optional[str]:
    stripped = line.strip()
    if not stripped.startswith('"'):
        return None
    end = stripped.find('"', 1)
    if end < 0:
        return None
    return stripped[1:end]


def is_forbidden_import(package: str) -> bool:
    for prefix in FORBIDDEN_IMPORT_PREFIXES:
        if package == prefix or package.startswith(prefix + "/"):
            return True
    return False


def main() -> int:
    failures = []
    for module in REUSABLE_MODULES:
        module_dir = ROOT / module
        if not module_dir.exists():
            failures.append((module_dir, 0, "missing reusable module"))
            continue
        for path in iter_package_manifests(module_dir):
            text = path.read_text(encoding="utf-8")
            for lineno, line in enumerate(text.splitlines(), start=1):
                package = parse_imported_package(line)
                if package is not None and is_forbidden_import(package):
                    failures.append((path, lineno, package))

    if failures:
        print("module boundary audit failed:", file=sys.stderr)
        for path, lineno, package in failures:
            rel = path.relative_to(ROOT)
            print(f"{rel}:{lineno}: forbidden import {package}", file=sys.stderr)
        return 1

    print("module boundary audit passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
