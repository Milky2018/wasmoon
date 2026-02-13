# Native Compile Progress API

Wasmoon now exposes compile progress events during JIT compilation:

- Package: `Milky2018/wasmoon/cli/main`
- API:
  - `compile_module(module_bytes, opt_level?, enable_dwarf?, on_progress?) -> PrecompiledModule?`

## Progress callback

`on_progress` receives `CompileProgress` events with:

- `stage`: `parse`, `verify`, `translate`, `optimize`, `lower`, `regalloc`, `codegen`, `link`, `done`, `failed`
- `func_idx`, `func_name` (for per-function stages)
- `total_funcs`, `compiled_funcs`
- `elapsed_us` (microseconds since compile start)
- `message` (set on failed stage)

This API is intended for deterministic progress UI and better operator visibility during module compilation.
