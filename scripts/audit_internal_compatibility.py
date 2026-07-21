#!/usr/bin/env python3
"""Reject retired project-owned compatibility paths."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]

FORBIDDEN_FILES = [
    "modules/wasmoon/testsuite/aarch64_candidate_test.mbt",
]

FORBIDDEN_TEXT = {
    "modules/milkir/egraph/egraph.mbt": [
        "pub fn EGraph::saturate(",
    ],
    "modules/milkir/egraph/rules_all.mbt": [
        "pub fn standard_rules_indexed(",
    ],
    "modules/milkir/egraph/rules_skeleton.mbt": [
        "pub fn skeleton_rules(",
    ],
    "modules/milkir/egraph/rules_remat.mbt": [
        "pub fn remat_rules(",
    ],
    "modules/milkir/egraph/rules_select.mbt": [
        "pub fn select_rules(",
    ],
    "modules/milkir/egraph/rules_spaceship.mbt": [
        "pub fn spaceship_rules(",
    ],
    "modules/milkir/egraph/rules_vector.mbt": [
        "pub fn vector_rules(",
    ],
    "modules/milkir/egraph/pkg.generated.mbti": [
        "standard_rules_indexed",
        "pub fn EGraph::saturate(Self, Array[RewriteRule]",
        "pub fn legality_sensitive_rules() -> Array[RewriteRule]",
        "pub fn skeleton_rules()",
        "pub fn remat_rules()",
        "pub fn select_rules()",
        "pub fn spaceship_rules()",
        "pub fn vector_rules()",
    ],
    "modules/wasmoon_jit/jit_ffi/ffi.mbt": [
        "c_dwarf_capture_backtrace(",
        "c_jit_get_memory_fill_mem0_ptr",
        "c_jit_get_memory_copy_mem0_ptr",
    ],
    "modules/wasmoon_jit/jit_ffi/dwarf.c": [
        "wasmoon_dwarf_capture_backtrace(",
    ],
    "modules/wasmoon_jit/jit_ffi/jit.c": [
        "wasmoon_jit_memory_fill_mem0(",
        "wasmoon_jit_memory_copy_mem0(",
        "wasmoon_jit_get_memory_fill_mem0_ptr(",
        "wasmoon_jit_get_memory_copy_mem0_ptr(",
    ],
    "modules/wasmoon_jit/jit_ffi/jit_internal.h": [
        "memory_grow_ctx_internal",
        "memory_size_ctx_internal",
        "memory_fill_ctx_internal",
        "memory_copy_ctx_internal",
    ],
    "modules/wasmoon_jit/jit_ffi/memory_ops.c": [
        "memory_grow_ctx_internal",
        "memory_size_ctx_internal",
        "memory_fill_ctx_internal",
        "memory_copy_ctx_internal",
    ],
    "modules/wasmoon_jit/jit_ffi/pkg.generated.mbti": [
        "c_dwarf_capture_backtrace(Int64",
        "c_jit_get_memory_fill_mem0_ptr",
        "c_jit_get_memory_copy_mem0_ptr",
    ],
    "modules/wasmoon_jit/native_runtime.mbt": [
        "direct_call_idx_memory_fill_mem0",
        "direct_call_idx_memory_copy_mem0",
        "DirectCallStubSet",
        "DirectCallStubInstallError",
        "install_direct_call_stubs_for_target",
        "build_aarch64_direct_call_stub",
        "build_x64_direct_call_stub",
    ],
    "modules/wasmoon_jit/pkg.generated.mbti": [
        "direct_call_idx_memory_fill_mem0",
        "direct_call_idx_memory_copy_mem0",
        "DirectCallStubSet",
        "DirectCallStubInstallError",
        "install_direct_call_stubs_for_target",
        "build_aarch64_direct_call_stub",
        "build_x64_direct_call_stub",
    ],
    "modules/wasmoon/jit/jit_runtime.mbt": [
        "install_direct_call_stubs",
    ],
    "modules/wasmoon_jit/runtime_symbols.mbt": [
        "wasmoon.runtime.memory_fill_mem0",
        "wasmoon.runtime.memory_copy_mem0",
        "-21003",
        "-21005",
    ],
    "modules/wasmoon/executor/instantiate.mbt": [
        "Legacy format: function index as i32",
    ],
    "modules/wasmoon/executor/exec_instr.mbt": [
        "Legacy format: function index as i32",
    ],
    "modules/wasmoon/executor/instr_gc.mbt": [
        "Legacy format: function index as i32",
    ],
}


def main() -> int:
    failures = []
    for relative in FORBIDDEN_FILES:
        if (ROOT / relative).exists():
            failures.append(f"retired file remains: {relative}")
    for relative, markers in FORBIDDEN_TEXT.items():
        path = ROOT / relative
        if not path.exists():
            failures.append(f"expected source file is missing: {relative}")
            continue
        text = path.read_text(encoding="utf-8")
        for marker in markers:
            if marker in text:
                failures.append(f"{relative}: retired marker {marker!r}")

    if failures:
        print("internal compatibility audit failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("internal compatibility audit passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
