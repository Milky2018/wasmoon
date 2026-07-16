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
    "modules/machv_legacy",
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

LEGACY_MODULE = "Milky2018/machv_legacy"

ALLOWED_LEGACY_IMPORT_MANIFESTS = {
    "modules/aarch64_target/moon.mod",
    "modules/aarch64_target/moon.pkg",
    "modules/machv_emit/isaregs/moon.pkg",
    "modules/machv_emit/moon.mod",
    "modules/machv_emit/moon.pkg",
    "modules/machv_regalloc/layout/moon.pkg",
    "modules/machv_regalloc/moon.mod",
    "modules/machv_regalloc/moon.pkg",
    "modules/milkir_machv/lower/moon.pkg",
    "modules/milkir_machv/lower/peephole/moon.pkg",
    "modules/milkir_machv/moon.mod",
    "modules/milkir_machv/moon.pkg",
    "modules/wasm_isa_lower/moon.mod",
    "modules/wasm_isa_lower/moon.pkg",
    "modules/wasmoon/cmd/wasmoon/commands/moon.pkg",
    "modules/wasmoon/moon.mod",
    "modules/wasmoon/moon.pkg",
    "modules/wasmoon_jit/moon.mod",
    "modules/wasmoon_jit/moon.pkg",
    "modules/x64_target/moon.mod",
    "modules/x64_target/moon.pkg",
}


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


def is_legacy_import(package: str) -> bool:
    module_name = package.split("@", 1)[0]
    return module_name == LEGACY_MODULE or module_name.startswith(LEGACY_MODULE + "/")


def legacy_import_is_allowed(path: Path) -> bool:
    rel = path.relative_to(ROOT)
    if rel.parts[:2] == ("modules", "machv_legacy"):
        return True
    return rel.as_posix() in ALLOWED_LEGACY_IMPORT_MANIFESTS


def main() -> int:
    failures = []
    legacy_import_manifests = set()
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

    for path in ROOT.glob("modules/*/moon.mod"):
        text = path.read_text(encoding="utf-8")
        for lineno, line in enumerate(text.splitlines(), start=1):
            package = parse_imported_package(line)
            if (
                package is not None
                and is_legacy_import(package)
            ):
                if legacy_import_is_allowed(path):
                    legacy_import_manifests.add(path.relative_to(ROOT).as_posix())
                else:
                    failures.append((path, lineno, "legacy import outside allowlist"))

    for path in ROOT.glob("modules/**/moon.pkg"):
        text = path.read_text(encoding="utf-8")
        for lineno, line in enumerate(text.splitlines(), start=1):
            package = parse_imported_package(line)
            if (
                package is not None
                and is_legacy_import(package)
            ):
                if legacy_import_is_allowed(path):
                    legacy_import_manifests.add(path.relative_to(ROOT).as_posix())
                else:
                    failures.append((path, lineno, "legacy import outside allowlist"))

    for rel in sorted(ALLOWED_LEGACY_IMPORT_MANIFESTS - legacy_import_manifests):
        failures.append((ROOT / rel, 0, "stale legacy import allowlist entry"))

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
