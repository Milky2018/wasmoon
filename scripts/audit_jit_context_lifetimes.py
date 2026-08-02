#!/usr/bin/env python3
"""Reject managed JIT context APIs that let raw VMContext pointers escape."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RAW_CONTEXT_EXTRACTOR = "c_jit_context_ptr("


def audit_repo(root: Path) -> list[str]:
    jit_package = root / "modules/wasmoon_jit"
    native_ffi = jit_package / "native_ffi.mbt"
    public_interfaces = (
        jit_package / "pkg.generated.mbti",
        root / "modules/wasmoon/jit/pkg.generated.mbti",
    )
    failures: list[str] = []

    if not native_ffi.is_file():
        failures.append(f"{native_ffi}: missing native FFI declarations")
    extractor_sources: list[Path] = []
    for source in jit_package.rglob("*.mbt"):
        if source == native_ffi:
            continue
        if RAW_CONTEXT_EXTRACTOR in source.read_text():
            extractor_sources.append(source)
    if len(extractor_sources) > 1:
        failures.append(
            "raw context extraction must stay confined to one implementation "
            f"file; found {[str(path) for path in extractor_sources]}"
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
        text = interface.read_text()
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
