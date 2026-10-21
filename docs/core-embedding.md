# Core embedding boundaries

The portable syntax model, checked embedding handles, and native execution ABI
have different contracts. A public symbol in an engine package is not by itself
a portable, provenance-safe embedding operation. This inventory covers the
Core parser/validator, executor, runtime, and their native/Component adapters.
It does not claim a security certification or host-memory isolation from native
FFI callers.

## Validation evidence and syntax ownership

`wasm_core/types.Module` remains an editable model for parsers, encoders and
transformations. Its section arrays and function-name map are editable. Nested
syntax, including function parameters/results, instructions, block bodies,
locals, struct fields, supertype lists, and element expressions, uses immutable
`ReadOnlyArray` values. Builders freeze their mutable arrays when constructing
these values. `Bytes` is immutable.

`Module.snapshot()` copies section arrays and the name map. Immutable syntax
values can be shared without recursively copying every instruction on every
function allocation or call.

`wasm_core/validator.ValidatedModule::new(module)` snapshots **before** validating.
Its representation is private. `snapshot()` returns detached editable sections;
`function()` exposes immutable function syntax and signature values. Editing the
original module or a returned snapshot cannot invalidate the accepted module.
Both validation entry points reject malformed raw-model shapes, negative unsigned
indices, wrong-kind type references, and invalid instruction immediates.
Subtype parents must precede children and there may be at most one parent, as in
[Core type validation](https://webassembly.github.io/spec/core/valid/types.html).
Recursive group IDs must describe contiguous ranges; `-1` is the sole passive
data-segment sentinel in this model.

All public executor instantiation entry points either validate a snapshot or
require `ValidatedModule`. Invalid models produce `RuntimeError::InvalidModule`
before Store allocation. Execution enables the supported stack-switching
feature when validating raw models. Explicit proof construction can choose its
validation features. Validation evidence is reusable across instantiations.
The `*_unstarted` entry point deliberately leaves initialization/start execution
to its engine caller; use `*_with_init` for a standalone initialized instance.

## Interface inventory

| Surface | Classification | Contract |
| --- | --- | --- |
| `types.Module`, parsers, encoders, `Module.snapshot` | Portable tooling | Editable sections; immutable nested syntax. A raw model is not validation evidence. |
| `validator.validate_module`, `validate_module_with_context` | Validation operations | Check input at the time of the call; return no reusable ownership proof. |
| `validator.ValidatedModule` | Protected validation evidence | Private accepted snapshot; returned containers do not alias it. |
| Executor `instantiate_module*`, `instantiate_with_linker*`, `instantiate_validated_module*` | Checked instantiation | Validate or consume protected evidence, check imports and Store membership, publish coherent instances. |
| `executor.Function` and `runtime.RootedValue` | Checked embedding calls | Bind a function to a live instance/Store; check argument/result types, reference provenance, and root lifetimes. Sync and async interpreter execution. |
| `Store.guest_exception`, `GuestException.throw_into_guest` | Opt-in guest exception transport | Bind a Store-local tag and validated rooted payload to a one-shot owner; transfer it through an explicitly throwing callback or async completion. |
| `Store`, `ModuleInstance`, `Imports`, `Linker`, `Caller` ownership | Checked ownership | Private Store tables, immutable instance maps, Store identity, rollback invalidation, checked registration and lookup. |
| `Memory` loads/stores/copy/grow | Checked resource operations | Descriptor bounds/lifetime checks; Store adoption is exclusive except explicit shared-memory imports. Legacy non-raising read/write helpers preserve their documented fallback behavior. |
| `Table`/`GlobalInstance` numeric operations | Checked shape and lifetime | Enforce bounds, mutability, value category and resource ownership. Raw reference values retain the Store-local preconditions below. |
| Counts, stats, type/address metadata, `get_exn`, stack/frame snapshots | Diagnostics and read-only inspection | Detached containers or immutable values; integer addresses are observations, not transferable handles. |
| Raw `Value`, `ExternVal`, integer addresses, `Imports.add_*`, `host_exports`, `Store.new_instance` | Store-local engine/linking seams | Caller supplies indices from the named Store and the appropriate type graph. Instance publication checks counts, signatures, resource limits and definition identity. Integers alone cannot prove their Store of origin. |
| `call_func_by_index*`, `call_exported_func*`, raw host callbacks, `eval_const_expr` | Raw execution seams | Check live instance, index and call shape at entry. Caller owns provenance/rooting of raw reference arguments/results; callbacks uphold their signature and Store-local reference contract. Prefer `Function` for reference-bearing embedding calls. |
| `Store.root_raw_value`, `root_result_value`, `borrow_*rooted_value` | Explicit raw-value bridge | Entry verifies liveness; caller guarantees raw reference origin, kind and declared result type. It cannot recover provenance from a naked integer. |
| `Store.alloc_struct/array/exn`, raw GC mutation, `set_module_types`, continuations and root leases | Engine operations | Require a validated type context, correct field/payload types, live Store-local references, and balanced continuation/root ownership. Not a general API for untrusted host-written GC graphs. |
| Standalone `MarkSweepHeap`, `GCObject`, `StructInstance`, `ArrayInstance`, operand `Stack`, `Frame` | Low-level engine data structures | May be assembled for engine work; none exposes the private heap or operand state of an executing Store. |
| `ModuleInstance.validated_*_type_at`, model `validated_*` lookups | Validated-index preconditions | Caller must supply an in-range index of the named kind. Violations are engine programming errors; use checked model lookups for arbitrary indices. |
| `JITModuleContext`, `component_native`, `CoreExecutionEngine` | Native/Component engine adapters | Check Store/instance affinity, snapshot metadata, and reject stale bindings. A native Component session is affine to one Store. Interpreter engines can serve different Stores. |
| `wasmoon_jit`, compiled `JITModule`, native context/heap/callable/funcref/global bindings, raw pointers and callbacks | Trusted native ABI capabilities | Artifact compatibility, pointer lifetime, synchronization and ABI correctness remain caller obligations. Portable handles do not make arbitrary C pointers or host callbacks safe. |

Raw engine seams are retained because the interpreter, WAST runner, Component
adapter and native ABI need Store-local operations. They are explicitly distinct
from the checked reference-bearing embedding path. Supplying a forged raw
reference through such a seam violates its precondition; it is not equivalent
to constructing a `RootedValue` through a checked function result.

## Store and handle lifetimes

`ModuleInstance` construction and field assignment are private to the runtime.
Address maps and type graphs are immutable. An instance carries a Store identity
and registration slot. Every call verifies both identity and the actual object
in that slot. Function handles also retain a per-allocation lifetime token, so
rolling back an appended host export cannot retarget its handle to a replacement
function even when the host namespace itself remains live. Rollback invalidates the slot; allocating a new object at the same
integer address cannot revive an old handle. A closed Store rejects entry.
`Imports(store)` similarly prevents resolving A's import map in B's Store.

`Function::from_export(store, instance, name)` binds the checked triple. Its
`call`/`call_async` methods use opaque `RootedValue` arguments and results.
Primitive values can cross Stores; references cannot. A reference result owns a
GC root lease. MoonBit RC releases that lease when the last owning value is
dropped, using a managed native finalizer; `close()` releases it early and is
idempotent. Roots protect arguments through async suspension and are retired on
cancellation. `Store.close()` retires outstanding roots. Scalar extraction never
returns a raw reference index.

A retained `Function` or reference `RootedValue` keeps its Store reachable;
explicit `Store.close()` still makes it unusable. Resource identity tokens and
native engine affinity tokens do not retain the Store, avoiding ownership cycles.

A Memory, Table or Global object has one Store owner. Re-adopting the same object
in that Store returns its existing address. Another Store receives `ForeignStore`.
Rollback invalidates adopted objects, rather than allowing them to be rebound
under a reused address. `alloc_shared_mem` explicitly creates an independent
shared-memory descriptor handle: closing one Store leaves the other's handle
usable. Cross-module imports within one Store retain the same resource identity.

The native context owns detached immutable metadata and binds to one live
instance. Reusing an instance index in a second Store or after rollback cannot
reuse its context. Component engine entry checks membership before dispatch;
native sessions additionally reject reuse with a different Store or after close.

## Defined failures

- Malformed syntax: validation error, mapped to `InvalidModule` by executor APIs.
- Foreign Store/instance, resource adoption or rooted reference: `ForeignStore`.
- Unregistered, rolled-back, released or inconsistently bound handle: `InvalidHandle`.
- Closed Store: `StoreClosed`; closed memory operations retain `MemoryClosed`.
- Missing/out-of-range function: `UndefinedElement`; bad call shape: `TypeMismatch`.
- Native adapters preserve their structured error wrappers, including
  `JITCoreCallError::HostInvocation` and `ComponentRuntimeError`.

## Compatibility and release notes

This is a source-breaking Core embedding change and belongs in the next minor
release with the workspace's lockstep version policy. It does not change the
Wasm binary format. This work does not publish a release or change versions.

Migrate editable nested syntax builders with `ReadOnlyArray::from_array(builder)`;
replace section elements instead of mutating accepted instruction arrays. Use
`ValidatedModule` for reusable validation, and pass `(proof, local_index)` to
`Store.alloc_func`. Replace direct Store-table inspection with `counts`, checked
getters and immutable metadata. Replace forged instance records with executor
instantiation or checked host namespace factories. Construct `Imports(store)`.
Use `Function`/`RootedValue` rather than moving raw references between calls or
Stores. Adopt ordinary resources in one Store; use `alloc_shared_mem` explicitly
for shared memory. Create one native Component session per Store.

The [executable embedding example](../modules/wasmoon/executor/README.mbt.md)
and [boundary evidence](evidence/core-boundaries-2026-10-15/README.md) record the
supported path and current verification scope.

## Resource policy

Pass an explicit `ResourceBudget` to related Stores to share finite logical
memory, table, GC, instance, code and pending-work quotas. Use
`Store.decode_module` for bounded binary expansion and
`Store.with_execution_limits` for scoped cooperative execution controls.
`component.ComponentRuntime` exposes the same budget and execution-scope policy.
The [resource inventory](resource-budgets.md) defines units, admission/release,
Core compilation integration and the limits that still need OS isolation.

## Native guest trap frames

Newly compiled internal guest functions maintain an unwindable frame-pointer
chain on AArch64 and x64, including leaves. AArch64 establishes its 16-byte
FP/LR record before probing the remaining frame allocation; x64 keeps the
existing RBP setup even for otherwise empty internal frames. Platform functions
retain their existing ABI policy. Tail calls intentionally remove their caller.

A resumable native trap copies up to the existing 32 native frame records into
its activation before the fiber is released. Walking is bounded by that fiber's
usable stack, not by whichever DWARF owner was most recently registered. Windows
samples the saved frame's committed readable region in the owned fiber allocation
and copies its chain before restoring the overflow guard. The
module's owned TrapReport resolves every captured guest PC it owns and preserves
recursive repetitions. Caller return addresses resolve using their preceding
byte so a range-end return cannot name the next function. Names and indices
remain readable after the context/Store closes; PCs are diagnostic integers,
not permission to access released executable memory. Native offsets are not
Wasm binary/source offsets. Missing frame records and the fixed capture limit
remain bounds on diagnostic completeness.

Retaining `JITModule.register_dwarf()` enables the same installed-range lookup
for debugger/backtrace names. It does not establish or authorize stack bounds.

## Explicit exceptions from host callbacks

Register a synchronous callback with `Store.alloc_throwing_host_func` or
`alloc_throwing_host_func_with_caller` when its ABI explicitly permits guest
exceptions. Existing `alloc_host_func` signatures and `RuntimeError` semantics
are unchanged. Guest import signatures do not change.

```mbt
let tag = store.alloc_tag({ params: [I32], results: [] })
let callback = store.alloc_throwing_host_func(fn(_) raise {
  let exception = store.guest_exception(tag, [RootedValue::i32(42)])
  defer exception.close()
  exception.throw_into_guest()
})
```

The tag address must come from this Store (`alloc_tag` or an instance's
`tag_addrs`). Integers alone cannot establish their original Store. Creation
checks the tag, payload arity/kinds, rooted reference provenance and concrete
reference subtyping against the tag's owning module. Use module-owned tags for
concrete reference types; a host-created tag without an owning type graph can
use scalar or abstract-reference parameters. Foreign rooted payloads and foreign
exception delivery fail with `ForeignStore`; invalid/rolled-back handles fail
with `InvalidHandle`. Reusing a rolled-back tag address cannot revive an old
prepared exception.

`GuestException` owns a separate root lease, so its input `RootedValue` handles
may be closed after creation. `throw_into_guest` never returns and moves the
owner into the typed `HostGuestException` transport before host defers execute.
The original handle and all its aliases are consumed; their deferred `close`
is safe. Construct a fresh exception for each throw. Explicitly close discarded
handles on wasm; native RC also releases their cleanup owner. Store close
retires outstanding roots. Each prepared exception reserves one `PendingWork`
unit through its root lease, including empty/scalar payloads.

Prepared handles participate in instantiation rollback until handoff. Once an
executor owns the lease, guest liveness and invocation cleanup govern it; an
outer rollback must not revoke an already handed-off root lease.

Guest `try_table` can catch the explicit exception by tag or with `catch_all`.
Ordinary host errors, traps, cancellation and resource failures remain invocation
failures. The runtime never converts all failures into catchable exceptions.
The raw interpreter `*_with_exception` APIs report uncaught tag/payload values;
ordinary interpreter calls report `UncaughtException`. Native calls keep their
recoverable `JITCoreCallError::Trap("uncaught exception")` boundary. Neither
channel aborts the process merely because the guest has no matching handler.

Async registrations already accept typed errors through `Error`. Use the same
`guest_exception(...).throw_into_guest()` operation there: an owned exception
may span an await, and each invocation's async driver retains its completed
payload until delivery/cleanup. Cancellation and late completion retire the
owner. Concurrent calls have independent completions; no Store-global pending
exception slot is used.

`HostGuestException::from_error` lets a host interceptor recognize the transport.
An interceptor that discards it must close the contained exception rather than
silently dropping portable ownership. `FuncInst.invoke_sync_host`,
`HostCallOutcome` and `Store.take_guest_exception` are low-level execution
bridges: a direct caller owns any transferred `GcRootLease` and must release it
after incorporating the payload into guest roots, or on failure. Interpreter
and native adapters perform that handoff automatically, including mixed SIMD
and reference payloads.
