#!/usr/bin/env python3
"""Reject unscoped use of raw pointers from managed JIT contexts."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RAW_EXTRACTOR = "c_jit_context_ptr("


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
        for block in text.split("///|"):
            if RAW_EXTRACTOR not in block:
                continue
            if re.search(r'extern\s+"c"\s+fn\s+c_jit_context_ptr\b', block):
                continue

            body_start = block.find("{")
            header = block[:body_start]
            assignments = list(
                re.finditer(
                    r"\blet\s+([A-Za-z_]\w*)\s*=\s*"
                    r"c_jit_context_ptr\(\s*([^)]+?)\s*\)",
                    block,
                )
            )
            if (
                body_start < 0
                or not re.search(
                    r"\bfn(?:\[[^]]+\])?\s+"
                    r"(?:[A-Za-z_]\w*::)?[A-Za-z_]\w*\s*\(",
                    header,
                )
                or block.count(RAW_EXTRACTOR) != len(assignments)
            ):
                failures.append(
                    f"{source}: raw context extraction must occur in a scoped "
                    "accessor"
                )
                continue

            callbacks = re.findall(
                r"\b([A-Za-z_]\w*)\s*:\s*\(\s*Int64\s*\)\s*->",
                header,
            )
            if not callbacks:
                failures.append(
                    f"{source}: raw context extraction must occur in a scoped "
                    "accessor"
                )
                continue

            keep_alives = list(
                re.finditer(
                    r"\bdefer\s+c_jit_context_keep_alive\(\s*([^)]+?)\s*\)",
                    block,
                )
            )
            for extraction in assignments:
                pointer, owner = extraction.groups()
                owner = "".join(owner.split())
                keep_alive = next(
                    (
                        match
                        for match in keep_alives
                        if match.start() > extraction.end()
                        and "".join(match.group(1).split()) == owner
                    ),
                    None,
                )
                if keep_alive is None:
                    failures.append(
                        f"{source}: raw context owner is missing a managed "
                        "keep-alive"
                    )
                    continue

                first_use = re.search(
                    rf"\b{re.escape(pointer)}\b", block[extraction.end() :]
                )
                if (
                    first_use is not None
                    and extraction.end() + first_use.start() < keep_alive.start()
                ):
                    failures.append(
                        f"{source}: managed keep-alive must be registered before "
                        "its first use"
                    )
                    continue

                if not any(
                    re.search(
                        rf"\b{re.escape(callback)}\s*\(\s*"
                        rf"{re.escape(pointer)}\b",
                        block[keep_alive.end() :],
                    )
                    for callback in callbacks
                ):
                    failures.append(
                        f"{source}: raw context pointer must be consumed by the "
                        "scoped accessor callback"
                    )

    forbidden_exports = (
        "NativeJITContext::ptr",
        "JITModule::get_context_ptr",
        "JITModule::get_func_table_ptr",
    )
    forbidden_raw_functions = (
        "pub fn gc_setup(",
        "pub fn gc_teardown(",
        "pub fn gc_set_context_heap_ptr(",
        "pub fn gc_begin_frame(",
        "pub fn gc_end_frame(",
        "pub fn gc_set_root_scratch(",
        "pub fn gc_set_safepoint_table(",
        "pub fn gc_use_func_safepoints(",
        "pub fn setup_type_cache_from_types(",
        "pub fn context_func_table_ptr(",
        "pub fn throw_exception_tag(",
        "pub fn throw_exception_values(",
        "pub fn setup_segments(",
        "pub fn clear_segments(",
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
        for signature in forbidden_raw_functions:
            if signature in text:
                failures.append(
                    f"{interface}: exposes raw context operation {signature}"
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
