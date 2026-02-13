# Native Preflight Validation API

Wasmoon now provides a lightweight preflight package for native integrations:

- Package: `Milky2018/wasmoon/preflight`
- APIs:
  - `validate_module(module_bytes : Bytes) -> PreflightResult`
  - `validate_jit(module_bytes : Bytes, opt_level? : Int = 2) -> PreflightResult`

## What it validates

`validate_module`:
- Binary parse check.
- WebAssembly semantic validation.

`validate_jit`:
- Includes all `validate_module` checks.
- Runs IR translation, lowering, and register allocation over all local functions.

`validate_jit` is intentionally non-emitting in this phase (no machine-code emission), so integrations can run preflight safely and collect structured diagnostics.

## Result format

`PreflightResult` includes:
- `ok : Bool`
- `diagnostics : Array[PreflightDiagnostic]`
- `total_funcs : Int`
- `checked_funcs : Int`

Each `PreflightDiagnostic` includes:
- `severity` (`error` / `warning`)
- `stage` (`parse`, `validate`, `translate`, `lower`, `regalloc`)
- `message`
- optional `func_idx`, `func_name`
