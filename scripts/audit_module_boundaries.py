#!/usr/bin/env python3
"""Audit reusable compiler-infrastructure module dependency boundaries."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]

REUSABLE_MODULES = [
    "modules/wasm_core",
    "modules/milkir",
    "modules/machv",
    "modules/regalloc",
    "modules/machv_regalloc",
    "modules/machv_emit",
    "modules/aarch64_target",
    "modules/x64_target",
]

FORBIDDEN = [
    "Milky2018/wasmoon",
    "Milky2018/wasmoon/ir",
    "Milky2018/wasmoon/vcode",
    "@wasmoon",
]


def iter_sources(module_dir: Path):
    for path in module_dir.rglob("*"):
        if path.is_file() and path.suffix in {".mbt", ".pkg"}:
            yield path


def main() -> int:
    failures = []
    for module in REUSABLE_MODULES:
        module_dir = ROOT / module
        if not module_dir.exists():
            failures.append((module_dir, 0, "missing reusable module"))
            continue
        for path in iter_sources(module_dir):
            text = path.read_text(encoding="utf-8")
            for lineno, line in enumerate(text.splitlines(), start=1):
                for needle in FORBIDDEN:
                    if needle in line:
                        failures.append((path, lineno, needle))

    if failures:
        print("module boundary audit failed:", file=sys.stderr)
        for path, lineno, needle in failures:
            rel = path.relative_to(ROOT)
            print(f"{rel}:{lineno}: forbidden dependency {needle}", file=sys.stderr)
        return 1

    print("module boundary audit passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
