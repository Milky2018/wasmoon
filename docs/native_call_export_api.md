# Native Controlled `call_export` API

Wasmoon now provides a structured export-invocation API in the `executor` package:

- Package: `Milky2018/wasmoon/executor`
- API: `call_exported_func_with_options(store, instance, name, args, options?)`

## Returned shape

`call_exported_func_with_options` returns `CallExportResult`:

- `Ok(Array[Value])` on success.
- `Err(CallExportFailure)` on failure.

`CallExportFailure` includes:

- `kind : CallExportFailureKind`
- `message : String`
- `runtime_error : RuntimeError?`

## Failure categories

- `ExportNotFound`
- `NotFunctionExport`
- `Trap`
- `HostInvocation`
- `Cancelled`
- `UnsupportedOption`

This separates WebAssembly runtime traps (`Trap`) from host callback failures (`HostInvocation`) in a machine-readable way.

## Options

`CallExportOptions` fields:

- `timeout_ms : Int?`
- `fuel : Int?`
- `budget : Int?`
- `cancel : (() -> Bool)?`

Current support level:

- `cancel` is checked before invocation.
- `timeout_ms`, `fuel`, and `budget` are accepted but currently return `UnsupportedOption`, so embedders can do explicit capability probing.

## Backward compatibility

`call_exported_func(...)` remains unchanged and still raises `RuntimeError`.  
Host-call errors are still surfaced as the original runtime error in this legacy API.
