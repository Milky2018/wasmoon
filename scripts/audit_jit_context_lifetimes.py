#!/usr/bin/env python3
"""Reject managed JIT context APIs that let raw VMContext pointers escape."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
JIT_PACKAGE = ROOT / "modules/wasmoon_jit"
NATIVE_RUNTIME = ROOT / "modules/wasmoon_jit/native_runtime.mbt"
NATIVE_FFI = ROOT / "modules/wasmoon_jit/native_ffi.mbt"
PUBLIC_INTERFACES = (
    ROOT / "modules/wasmoon_jit/pkg.generated.mbti",
    ROOT / "modules/wasmoon/jit/pkg.generated.mbti",
)


def main() -> int:
    runtime = NATIVE_RUNTIME.read_text()
    ffi = NATIVE_FFI.read_text()
    failures: list[str] = []

    extraction_count = runtime.count("c_jit_context_ptr(")
    if extraction_count != 2:
        failures.append(
            "native_runtime.mbt must contain exactly the allocation check and "
            f"scoped extractor; found {extraction_count} context-pointer uses"
        )
    if "defer c_jit_context_keep_alive(self.handle)" not in runtime:
        failures.append("scoped context-pointer access is missing managed keep-alive")
    if ffi.count("c_jit_context_ptr(") != 1:
        failures.append("native_ffi.mbt must declare exactly one raw context extractor")
    for source in JIT_PACKAGE.rglob("*.mbt"):
        if source in (NATIVE_RUNTIME, NATIVE_FFI):
            continue
        if "c_jit_context_ptr(" in source.read_text():
            failures.append(f"{source}: bypasses scoped managed context access")

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
    for interface in PUBLIC_INTERFACES:
        text = interface.read_text()
        for export in forbidden_exports:
            if export in text:
                failures.append(f"{interface}: exposes forbidden raw-pointer API {export}")
        for signature in forbidden_raw_functions:
            if signature in text:
                failures.append(f"{interface}: exposes raw context operation {signature}")

    if failures:
        print("JIT context lifetime audit failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print("JIT context lifetime audit passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
