# Embedding resource budgets

`runtime.ResourceBudget` is an optional, explicitly shared policy. Pass the same
budget to related Stores or to `component.ComponentRuntime(resource_budget=Some(budget))`.
Unconfigured limits default to `Int64::MAX`; creating a budget without setting
finite limits is accounting, not isolation. Negative limits are rejected.

The policy counts logical resources. It is neither an RSS ceiling nor a promise
that a synchronous host callback or one optimizer pass can be preempted. Use an
OS process/container boundary for hard CPU and address-space isolation.

## Ownership and admission

Native allocation owners retain RC reservations. Closing one Store does not
return a shared memory's charge while another Store, native context, or managed
descriptor still owns it. Copies of a lease share one charge. Explicit release
and finalization are idempotent. Quota counters are atomic; this does not make
Stores, reservation resizing, or arbitrary host objects thread-safe. Use their
existing synchronization rules. Shared-memory growth resizes under its growth
lock.

A memory/table already attached to a different quota pool is rejected when
adopted into a budgeted Store. Related owners must share a pool; moving a live
allocation between pools would lose its existing admission. An unbudgeted Store
borrowing an already budgeted native allocation cannot remove that allocation's
quota. Trusted low-level native APIs remain allocator capabilities, not a guest
security boundary.

| Resource | Unit and owner | Admission | Return/reuse | Sharing and remaining physical costs |
| --- | --- | --- | --- | --- |
| `MemoryBytes` | Current logical linear-memory bytes, native descriptor | Initial allocation or adoption; before growth/commit | Last native descriptor owner | One charge for shared descriptors. Guard regions/reserved virtual address space, descriptors and allocator granularity are additional. |
| `TableElements` | Current reference slots, table/native owner | Minimum before array creation; growth before native allocation | Table close and last native owner | One shared reservation for runtime/native mirrors. Both representations, capacity and reference metadata consume additional bytes. |
| `GcBytes` | Struct `16 + 16*n`, array `32 + 16*n`; wrapper 16; exception `16 + 16*n` | Before payload copy/allocation; expanded arrays before temporary construction | Collection, transaction rollback, or owner release | Native and MoonBit exception mirrors charge separately. Heap capacity/high-water and allocator metadata are not payload bytes. |
| `GcObjects` | Retained GC identity slots plus live wrapper/exception records | Before allocating a slot/record | Reclaimed auxiliary records; heap rollback/close | Native GC identities are not reused; ordinary collection leaves tombstones charged. Interpreter free slots are reusable but its identity array remains charged. Do not interpret this counter as live objects. |
| `Instances` | Core and Component instances, including retained host call contexts | Core admission before validation/initialization; Component frame before initialization | Rollback or Store close | Re-registering an owned instance does not charge twice. Unconsumed admission tokens are caller-owned reservations; cancel or drop them. |
| `CodeBytes` | Function and trampoline machine-code lengths | Before staging/allocating executable memory | Rollback, installation release or last native mapping owner | Replacement must admit the peak old + new installation. Page rounding, debug metadata and allocator overhead are additional. |
| `PendingWork` | Component slots (tasks/threads/streams/futures/waitables), MoonBit root registrations, suspended Core executions, native root invocations and continuation bodies | Before registration/allocation | Retirement, completion/cancel, collection or close | A task may require multiple slots. Map replacement keeps its existing slot. Native continuation records retained by cancellation scopes stay charged until retirement. Native stacks are bounded by their configured per-stack size times admitted owners, not by a byte counter here. |
| `InputBytes` | Simultaneously decoded binary bytes; retained Component binary | Before the bounded decoder / Component preflight | Decoder exit; Component rollback/Store close | Nested/embedded copies can overlap and consume additional allowance. A caller-owned parsed AST is outside this counter after decode. |
| `CompilationUnits` | AST declarations, instructions, locals, type members, vector immediates, payload bytes and string code units; Component binary traversal bytes | Incremental shape admission before validation/canonicalization; retained per Core instance and Component binary | Temporary work exit; rollback/Store close | A conservative work/metadata proxy, not an IR-byte or optimizer CPU counter. Shared ASTs instantiated independently are charged independently. |
| `compilation_depth` | Maximum nested Core expression frames / Component binary scopes | Iterative preflight before recursive validation/lowering | Per operation; default 512 with a budget | Parser/type-validator structural limits remain independent. |

Budgeted native GC heaps deliberately use the common allocator instead of
unaccounted inline bump allocation. Unbudgeted heaps retain their existing
fast path.

Quota denial does not run arbitrary cancellation callbacks or force collection
from a half-constructed MoonBit object. Existing native GC slow paths may collect
and retry with precise roots; otherwise an embedder may collect with explicit
roots before retrying. Auxiliary-only registries are reclaimed by the existing
Store collection walk. Reaching their finite quota fails without publishing a
new record; it does not start an unbounded allocation/collection retry loop.

`memory.grow` and `table.grow` retain the Wasm result contract: policy denial
returns `-1`. Initial allocations and metadata admissions report
`RuntimeError::ResourceLimitExceeded(kind)`; Component facade errors preserve the
same kind. Actual allocation failure, module-declared maxima and ordinary traps
remain distinct.

Core instance initialization joins the existing instantiation transaction, or
creates its own. A failed minimum/growth-independent allocation returns newly
owned functions, memories, tables, instance reservations and heap state.
The Core-owned transaction commits before active segment initialization can
publish references into imported tables. A later segment/start trap must retain
those functions and their owning instance, including its quota; otherwise an
observable table entry would refer to reclaimed Store addresses. Close the
Store to return that retained charge. This is live ownership, not a failed
allocation leak. An enclosing Component transaction retains its existing root
commit boundary.

Rollback does not promise to undo arbitrary host side effects or guest writes
that survive through imported resources. Admission happens before those effects
when the denied resource is already knowable (for example the instance slot).
A provisional token is checked against the actual validated module; a token
admitted for a smaller AST cannot authorize a larger module.

## Decoding and compilation boundaries

For Core binaries use `Store::decode_module`. Its temporary input/work leases
are released on success or failure; the returned AST is caller-owned.
Instantiation separately admits and retains its accepted shape.
The reusable Core parser also exposes product-neutral `ParseLimits` and an
optional work-admission callback. It charges visited bytes (including type
pre-scans), expanded vectors and locals before allocation, and limits expression
nesting. Work exhaustion is structured, not an OOM or malformed-opcode alias.

The public Component runtime preflights shallow binary frames iteratively,
checks nested depth, and meters embedded Core expansion before invoking the
Component decoder/validator. Temporary aggregate work leases stay active across
that validation. Its retained binary and instantiated Core modules are admitted
again for their Store lifetimes. Passing an already parsed Component does not
retroactively account for the caller's earlier parsing/allocation.

The bounded Component native compiler checks execution control before its
validation stage and between function compilation stages. Core embedders using
the lower-level compiler explicitly keep `Store::admit_module_work(module)` alive
through validation/compilation and pass `store.resource_budget` to
`JITModule::load_artifact[_with_imports]`. Loading code without a budget is an
explicit unbudgeted low-level operation. Persistent artifact cache files are
host-owned disk resources, not executable code charges.

## Compute, suspension and cancellation

Use `Store::with_execution_limits` or
`ComponentRuntime::with_execution_limits` with `safepoints`, `timeout_ms`, and/or
`cancel`. Zero allowance/deadline and an already-cancelled callback reject before
entering the supplied closure. Nested scopes apply all parent policies. Captured
controllers survive delayed first polling and later continuation resumes; a
scheduler cannot reset their allowance by leaving the creation scope.

Safepoints are cooperative checkpoint units, **not** Wasm instruction fuel or
engine-independent cost. The interpreter checks while executing instructions;
native code must have cancellation safepoints enabled. Component native
artifacts enable them. A low-level artifact without safepoints is rejected by a
limited Core call with `ExecutionLimitsUnavailable`. Legacy unsupported
`CallExportOptions.fuel/budget` do not silently become instruction fuel.

Deadlines use elapsed monotonic time, including parked and host time. A blocking
host callback or a single synchronous parse/validation/optimizer operation is
checked at supported boundaries; it cannot be forcibly interrupted in-process.
Resource/shape limits bound admitted input to those operations but do not bound
all algorithmic complexity with a fixed wall-clock guarantee. Scoped controllers
do not arm reactor timers to wake an external wait: use `async.with_timeout`
around a join or host operation when cancellation must occur while awaiting I/O.

Pure async Component compute yields cooperatively so MoonBit async cancellation
can run. A compute yield remains runnable even with outstanding stream/future
operations; it is distinct from canonical suspension awaiting external progress.
A genuine canonical deadlock still fails and cancels its continuation. Cancellation consumes/unwinds parked continuations, invokes their
cleanup and returns root/task/native invocation reservations. Cleanup callbacks
remain idempotent. `Store.close` is terminal; native invocations must already be
returned or cancelled, as required by its existing ownership contract.

Policy exhaustion, elapsed timeout, cancellation and ordinary traps preserve
their different structured errors through interpreter/native and the public
Component facade. Core instances are reusable after a bounded call stops. A
Component trap poisons its canonical Store: reuse requires closing the runtime
and creating a fresh one, potentially sharing the released budget. This follows
the [Canonical ABI lockdown contract](https://github.com/WebAssembly/component-model/blob/main/design/mvp/CanonicalABI.md#embedding);
cleanup must not reset the poison flag just to make a subsequent call succeed.

## Limits outside this policy

- MoonBit runtime allocations/RC bookkeeping, native allocator metadata and
  initial GC heap capacity are not exact payload accounting.
- Host-created ASTs, host functions, canonical host values, externally retained
  snapshots, debug data and compiler IR/allocator high-water storage are not a
  hard byte budget. Shape admission limits accepted module size; it does not
  instrument every internal allocation or prove a complexity bound.
- HTTP connection/body/header limits, timers, framing and backpressure remain
  their existing policies. OS sockets, file handles, TLS buffers, host futures
  and host callback side effects require corresponding host policy.
- Native stacks retain their configured guards and per-stack size. Interpreter
  frame/value/control/reentry limits still apply independently.
- Scoped controllers are not a process-wide preemptive scheduler, and a budget
  shared across Stores is not automatic tenant discovery. Embedders choose the
  ownership scope and finite limits.

These are deliberate boundaries of the supported policy, not claims of perfect
sandbox resource isolation. For hard RSS/CPU/descriptor limits, run the runtime
behind OS limits and a supervisor that can terminate the worker.

## Implementation boundary

Policy and execution-scope methods stay in the runtime package because they
maintain the same private Store/heap ownership invariants. The native FFI adds
only atomic counters and RC reservations; it does not call MoonBit policy from
C allocation paths. Product-neutral parsing limits stay in `wasm_core/parser`.
The existing module-boundary check remains unchanged.

Local verification receipts and remaining platform acceptance are recorded in
[evidence](evidence/resource-budgets-2026-10-16/README.md) and
[ISS-627](../issues/ISS-627.md).
