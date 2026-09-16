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
- `TimedOut`
- `InvalidOption`
- `UnsupportedOption`

This separates WebAssembly runtime traps (`Trap`) from host callback failures (`HostInvocation`) in a machine-readable way.

## Options

`CallExportOptions` fields:

- `timeout_ms : Int?`
- `fuel : Int?`
- `budget : Int?`
- `cancel : (() -> Bool)?`

Current support level:

- `cancel` is checked before invocation and cooperatively at every Wasm function entry and loop header.
- Cancellation is invocation-local. The callback runs synchronously on the execution thread.
- A synchronous blocking host function is not interrupted while it runs; embedders must bound blocking host work separately.
- `timeout_ms` uses monotonic elapsed time from invocation entry, including host work and time parked by the engine. Zero times out before guest execution; negative values return `InvalidOption`.
- Deadlines are cooperative: they are checked at safepoints and before returning successful results. A blocking host call can exceed the deadline before returning. Traps and host failures retain their classification; timeout does not roll back guest or host side effects.
- `fuel` and `budget` still return `UnsupportedOption`.

## JIT cancellation

JIT cancellation is opt-in at compilation time. Compile with `compile_module(..., enable_cancellation=true)` (or the lower-level `compile_module_to_jit` equivalent) and invoke the resulting module with `JITModule::call_with_context_controlled(..., cancel=..., timeout_ms=...)`.

The controlled JIT call returns `JITCallResult`:

- `Completed(Array[Int64])`
- `Cancelled`
- `Failed(JITTrap)`
- `UnsupportedCancellation`
- `TimedOut`
- `InvalidTimeout` (negative `timeout_ms`)

The artifact manifest records whether cancellation safepoints were emitted. Requesting cancellation or a timeout on an uninstrumented artifact returns `UnsupportedCancellation` before machine code starts. The existing `call_with_context(...)` API remains unchanged.

A `JITModule` supports one active invocation at a time. Do not call the same module concurrently or re-enter it from its cancellation callback; the callback is stored in that module's execution context for the duration of the call.

## Backward compatibility

`call_exported_func(...)` remains unchanged and still raises `RuntimeError`.  
Host-call errors are still surfaced as the original runtime error in this API.

A deadline starts when the controlled API is called, after any compilation or
instantiation performed by the caller. The first observed timeout/cancellation
reason is latched. Deadline checks do not call user cancellation callbacks when
classifying results. Separate resumable/async invocation APIs do not implicitly
inherit the controlled API options; their existing cancellation and lifetime
contracts remain unchanged.
