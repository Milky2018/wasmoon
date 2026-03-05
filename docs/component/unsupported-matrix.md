# Component Unsupported Matrix (Wasmoon vs Wasmtime)

This document tracks `unsupported` paths in Wasmoon component-model code and classifies them with Wasmtime behavior.

## Method

- Wasmtime-side parser behavior checked with `wasm-tools parse` (same text format accepted by Wasmtime component toolchain).
- Wasmoon-side behavior checked with `moon run cmd/wasmoon-tools -- wat2wasm`.
- Runtime/validator notes are mapped to source-level constraints and tested via existing component tests.

## Legend

- **Decision = Implement**: Wasmtime accepts; Wasmoon must accept.
- **Decision = Structured Reject**: Wasmtime rejects; Wasmoon may reject but with stable/observable error.

## Matrix

| Area | Source location | Minimal repro | Wasmtime behavior | Wasmoon behavior | Decision |
|---|---|---|---|---|---|
| Parser UTF-8 names | `component/text_parser/component_wat.mbt:516` | `(component (import "模块/函数" (func)))` | Accept | Accept (after this PR) | Implement ✅ |
| Parser multiple result fields | `component/text_parser/component_wat.mbt:1045` | `(component (type (func (result u32) (result u32))))` | Reject | Reject | Structured Reject ✅ |
| Parser `future/stream` payload arity | `component/text_parser/component_wat.mbt:3303` | `(component (type (future u32 u32)))` | Reject | Reject | Structured Reject ✅ |
| Parser resource unknown option | `component/text_parser/component_wat.mbt:3323` | `(component (type (resource (rep i32) (foo 0))))` | Reject | Reject | Structured Reject ✅ |
| Parser import extra descriptors | `component/text_parser/component_wat.mbt:2705` | `(component (import "a" (func) (value u32)))` | Reject | Reject | Structured Reject ✅ |
| Validator unsupported core sort | `validator/component_model/component_type_sig.mbt:538` | Binary with unknown `core sort` tag | Reject | Reject (`UnsupportedCoreSort`) | Structured Reject ✅ |
| Runtime stream payload narrowing | `component/runtime_impl/type_mapping.mbt:21` | stream payload as unsupported valtype | Reject/Trap | Reject (`HostCallError`) | Structured Reject ✅ |
| Runtime unsupported param/result conversion | `component/runtime_impl/canon_convert.mbt:685` | canonical conversion with non-flattenable unsupported shape | Reject/Trap | Reject (`HostCallError`) | Structured Reject ✅ |
| CLI component-test unknown command | `cmd/wasmoon/commands/component_script.mbt:1151` | `{ "type": "assert_magic_typo", ... }` | N/A | Fail with `COMP_TEST_UNSUPPORTED_COMMAND` | Structured Reject ✅ |
| Runner unsupported masking guard | `scripts/run_component_wast.py:742` | `assert_invalid` / `assert_malformed` parse error with `unsupported` | N/A | Now hard-fail (no pass masking) | Structured Reject ✅ |

## Remaining sweep buckets

Large `unsupported` inventories still exist in these buckets and should continue to be tracked as explicit follow-ups:

1. **Type descriptor expansion** in `component_wat.mbt` (inline type/alias/import combinations).
2. **Runtime canonical lowering/lifting edge shapes** in `canon_convert.mbt`.
3. **Validator detail classification** for currently coarse unsupported branches.

Each new item must include:

- minimal repro,
- Wasmtime behavior evidence,
- explicit implement/reject decision,
- regression test.
