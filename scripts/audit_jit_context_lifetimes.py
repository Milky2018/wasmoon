#!/usr/bin/env python3
"""Keep native JIT context addresses out of MoonBit code."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN_RAW_CONTEXT_SEAMS = (
    "c_jit_context_ptr",
    '"wasmoon_jit_context_ptr"',
    "NativeJITContext::with_ptr",
)


def audit_repo(root: Path) -> list[str]:
    jit_package = root / "modules/wasmoon_jit"
    public_interfaces = (
        jit_package / "pkg.generated.mbti",
        root / "modules/wasmoon/jit/pkg.generated.mbti",
    )
    failures: list[str] = []

    if not jit_package.is_dir():
        return [f"{jit_package}: missing JIT package"]

    for source in jit_package.rglob("*.mbt"):
        text = source.read_text(encoding="utf-8")
        for seam in FORBIDDEN_RAW_CONTEXT_SEAMS:
            if seam in text:
                failures.append(
                    f"{source}: MoonBit must not expose raw JIT context seam {seam}"
                )

    forbidden_exports = (
        "NativeJITContext::ptr",
        "NativeJITContext::with_ptr",
        "JITModule::get_context_ptr",
        "JITModule::get_func_table_ptr",
    )
    for interface in public_interfaces:
        if not interface.is_file():
            failures.append(f"{interface}: missing public interface")
            continue
        text = interface.read_text(encoding="utf-8")
        for export in forbidden_exports:
            if export in text:
                failures.append(
                    f"{interface}: exposes forbidden raw-pointer API {export}"
                )
    return failures


def main() -> int:
    failures = audit_repo(ROOT)
    if failures:
        print("JIT context lifetime audit failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print("JIT context lifetime audit passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
