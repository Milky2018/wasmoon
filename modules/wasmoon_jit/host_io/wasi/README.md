# Native WASI host ABI

This package owns platform operations consumed by Wasmoon's shared WASI host.
Guest-memory decoding, rights policy, and engine dispatch belong to the caller.
Array extents and output capacities are checked by public MoonBit wrappers before
entering private raw externs. Resolver handles remain an internal ownership
protocol: use only handles returned by `c_resolver_start`, and drop them once.

The C translation units separate filesystem/capability traversal, sockets,
resolver worker ownership, polling, process operations, and directory encoding.
They remain in one package because they implement one native ABI consumed by the
same adapter; splitting them into public packages would expose platform details
without reducing caller responsibilities. Each worker's private state stays in
its owning translation unit. Shared Windows descriptor ownership lives in the
parent package.

JIT guest calls use the same host through the hostcall bridge. The JIT's
`wasi_context.c` preserves existing context APIs; it does not implement a second
set of guest WASI operations. VMContext layout stays shared with generated code
and is not split for file-count reasons.
