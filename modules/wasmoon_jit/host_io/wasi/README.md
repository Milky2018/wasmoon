# Native WASI host ABI

This package owns platform operations consumed by Wasmoon's shared WASI host.
Guest-memory decoding, rights policy, and engine dispatch belong to the caller.
Array extents and output capacities are checked by public MoonBit wrappers before
entering private raw externs. Resolver handles are opaque MoonBit external objects.
Explicit close is idempotent, and finalization closes an abandoned lookup. A
closed handle rejects further reads. Worker state is separately allocated: the
worker never touches MoonBit reference counts. Completion notification and
closing the pipe read end are serialized under the worker mutex, so cancellation
does not depend on process-wide SIGPIPE handling.

The C translation units separate filesystem/capability traversal, sockets,
resolver worker ownership, polling, process operations, and directory encoding.
They remain in one package because they implement one native ABI consumed by the
same adapter; splitting them into public packages would expose platform details
without reducing caller responsibilities. Each worker's private state stays in
its owning translation unit. Shared Windows descriptor ownership lives in the
parent package.

JIT guest calls use the same host through the hostcall bridge. VMContext contains
no duplicate WASI argument, environment, descriptor, preopen, or stdio state.
Only host exit status transport remains in `jit_ffi/host_exit.c`. The fixed-offset
prefix accessed by generated code is unchanged.

## Native API migration

The obsolete `JITModule::init_wasi`, `init_wasi_quiet`, `init_wasi_with_stdio`,
`NativeJITContext::init_wasi`, and native WASI capture/input methods have been
removed. They configured unused C state and did not configure shared hostcalls.
Build a `WasiContext` with `WasiContextBuilder` (args, environment, preopens,
stdin/stdout/stderr callbacks), register it with `register_wasi`, and link those
host imports into the JIT. The CLI and the WASI JIT test harness demonstrate this
single-owner path. `NativeJITContext::take_wasi_exit_code` remains available.

`c_resolver_start` now returns `(NativeResolverHandle, Int)`; the descriptor is
negative on startup failure. Pass the handle to `c_resolver_next` and
`c_resolver_drop`, never a pointer-valued integer. The higher-level
`native_resolver_start` retains its optional `NativeResolver` result; its handle
field now has the opaque type. Close or finalize only after unregistering any
readiness subscription; descriptors returned before close must not be reused.
