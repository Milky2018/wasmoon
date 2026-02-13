# Native Runtime Capability Query API

Wasmoon now exposes runtime capability and version queries in the `runtime` package.

## APIs

- `runtime_version() -> String`
- `supports_feature(feature : RuntimeFeature) -> Bool`
- `runtime_capabilities() -> RuntimeCapabilities`
- `supports_*()` helpers:
  - `supports_interpreter()`
  - `supports_jit()`
  - `supports_simd()`
  - `supports_relaxed_simd()`
  - `supports_reference_types()`
  - `supports_function_references()`
  - `supports_tail_call()`
  - `supports_exception_handling()`
  - `supports_gc()`
  - `supports_memory64()`
  - `supports_multi_memory()`
  - `supports_component_model()`
  - `supports_wasi_preview1()`
  - `supports_threads()`

## Capability keys

`RuntimeFeature` includes:

- `Interpreter`
- `JIT`
- `SIMD`
- `RelaxedSIMD`
- `ReferenceTypes`
- `FunctionReferences`
- `TailCall`
- `ExceptionHandling`
- `GC`
- `Memory64`
- `MultiMemory`
- `ComponentModel`
- `WasiPreview1`
- `Threads`

## Snapshot type

`RuntimeCapabilities` returns a structured snapshot with:

- `version`
- one boolean field per feature above

This is intended for integration-time capability gating and diagnostics without probing by trial execution.
