# Private context state: ownership and next reductions

Research date: 2026-09-30. Examined the uncommitted module-shaped layout on
`milky/research-module-context-layout`, based on b141554a. This report makes no
additional runtime changes. Sizes below are local macOS ARM64 C sizeof/offsetof
measurements, not RSS or an allocation trace. See the companion
[Wasmtime review](wasmtime-instance-state-followup.md) for pinned upstream sources.

## What the 216 bytes contain

Measured by compiling a temporary C program including `jit_internal.h` with the
installed MoonBit headers. The program prints sizeof/offsetof for every field;
no repository audit script was introduced. Declaration:
[jit_context.h](../modules/wasmoon_jit/jit_ffi/jit_context.h#L46).

| Group | Bytes in private state | Ownership |
| --- | ---: | --- |
| Layout and active execution pointers | 16 | Shared module descriptor; borrowed activation or lazy standalone fallback |
| GC type/canonical/function metadata and counts | 48 | Mixed Store type data, instance mapping and legacy address snapshot |
| Safepoint pointers and table count | 20 | Code metadata plus a mutable legacy current-table selection |
| Continuation arena/type and exception arena pointers | 24 | Store-bound arenas; context-owned continuation type bindings |
| Hostcall callback and closure | 16 | Instance-aware dispatcher |
| Invocation-control defaults | 24 | Context configuration, copied/retained into each invocation |
| Segment-state pointer | 8 | Mutable per-instance drop state, already lazy |
| Callable registry/local types/tags and counts | 32 | Shared registry plus instance mappings |
| Table binding pointer | 8 | Per-instance registrations needed when shared tables move |
| Memory/global ownership flags and WASI exit transport | 16 | Compatibility ownership and mutable exit result |
| Tail alignment | 4 | Padding |
| **Total** | **216** | |

This is not 216 bytes of disposable padding. Moving every group into a separate
allocation would add pointers, RC headers and allocator overhead while retaining
most payloads. Common execution/hostcall paths would gain indirections.

## Highest-value finding: empty safepoint tables

The [artifact loader](../modules/wasmoon/jit/jit_runtime.mbt#L260) calls the
registrar for every artifact function. The [registrar](../modules/wasmoon_jit/gc_helpers.mbt#L253)
builds a blob and offsets, including for empty safepoint lists. Empty lists
produce [an empty blob](../modules/wasmoon_jit/compiled_function.mbt#L70).
However [bind_func_safepoints](../modules/wasmoon_jit/jit_ffi/jit_context.c#L504)
calls `gc_alloc_func_safepoint_tables` before it handles empty payloads. That
allocator reserves `func_count * sizeof(wasmoon_gc_safepoint_table_t)`.
The [descriptor](../modules/wasmoon_jit/jit_ffi/jit_ffi.h#L79) measures **32 bytes**.

Consequently, loading an artifact with defined functions but no safepoints still
allocates the dense descriptor table. A 1,000-function context requests 32,000
bytes here alone. This is a source-path deduction using measured element size,
not a measured workload memory delta. It dominates a 32- or 96-byte header saving.

First fix: when binding empty metadata to a context that has no table, succeed
without allocating it. If a table already exists, empty rebinding must still
release the old entry. Validate missing-entry lookup, repeated clearing, failed
load cleanup and both engines. This needs no VMContext ABI redesign.

Second fix: prepare immutable blobs/offsets and their native descriptor owner once
per loaded artifact, then retain that owner from each context. The current path
rebuilds metadata for each load into a new context. Preserve stable descriptor
addresses for live/parked GC frames, and separate the mutable legacy
`gc_safepoint_table` selection from the immutable shared table. A frame must never
outlive the retained owner; releasing the caller's artifact reference must be safe.
Do not assume native code mappings themselves are already shared by this change.

## GC metadata cannot all be module-owned

[gc_setup](../modules/wasmoon_jit/gc_helpers.mbt#L334) creates a type-record array,
copies canonical and function type indices, and snapshots function addresses on
each setup. The [CLI call site](../modules/wasmoon/cmd/wasmoon/commands/run.mbt#L1473)
passes `store.module_types` and a canonical map computed from those types. These
are not necessarily local module indices or stable across Store growth.

A correct split is:

- Code-owned immutable data: safepoint payloads, local type definitions and static
  function signatures, prepared once at their actual sharing boundary.
- Store-owned identities: canonical/subtype registry and arena identity, shared
  with explicit lifetime and update/version rules.
- Instance bindings: local-to-Store indices, imported function targets, global
  cells, table registrations and segment drop state.
- Invocation state: live roots, exception payloads, cancellation/scheduling
  snapshots; retain the existing activation model.

The [legacy tagged-pointer lookup](../modules/wasmoon_jit/jit_ffi/gc_type_cache.c#L155)
and [segment fallback](../modules/wasmoon_jit/jit_ffi/segment_ops.c#L354) still use
function-address snapshots. Removing them requires proving the normal callable
identity path covers all representations and keeping standalone/raw API snapshot
semantics. A live borrowed function table is not automatically equivalent to a
snapshot after rebinding. Merely deleting the fallback would be a behavior change.

## Lower-priority header opportunities

Six array lengths occupy 24 bytes: GC types, canonical map, function types,
function addresses, callable local types and tags. Managed bindings already get
these from MoonBit array headers. The safepoint table count adds another 4 bytes
and currently equals the context function count. Removing all seven could reduce
the current 216-byte private struct to **184 bytes** after alignment, based on
its measured field layout. This is a potential layout calculation, not an
implemented or benchmarked result.

Before doing so, preserve the [raw setter contract](../modules/wasmoon_jit/jit_ffi/gc_type_cache.c#L307):
raw inputs are copied into RC arrays, and null/empty inputs must not be passed to
array-header reads. Type-record length uses a six-Int stride. Replacing cached
counts adds memory reads in subtype/GC helper paths; assess that cost rather than
assuming a smaller header is faster.

A lazy legacy compatibility owner could later contain address snapshots and
standalone-only metadata. Measure how often the normal path still needs it first.
A side allocation used by every instance is unlikely to be a useful optimization.

Keep hostcall closure ownership per instance for now:
[install_hostcall_dispatcher](../modules/wasmoon/wast/jit/support.mbt#L1518)
captures instance-aware state and async drivers. Keep invocation defaults and
activation snapshots intact. Store-wide cancellation state would break nested or
parked invocations. Likewise segment drop state and table bindings cannot become
shared immutable module data.

## Recommended sequence and evidence

1. Eliminate the empty safepoint allocation. Test 0/1/1,000-function no-safepoint
   cases, nonempty-to-empty rebinding, failure cleanup and parked frames.
2. Introduce one RC-owned immutable prepared safepoint object per loaded artifact;
   compare one and many instances, including releasing the artifact before them.
3. Separate Store-dependent type identity from module data and audit legacy
   address-snapshot usage. Handle Store growth and cross-module calls explicitly.
4. Only then benchmark deriving lengths and making compatibility state lazy.

For each stage record total requested bytes, allocation counts and lifecycle
retention, including metadata outside the fixed context. Use independent binaries
and A/A controls for timing. These research findings do not establish a new speedup,
a runtime failure, or a complete Wasmtime-vs-Wasmoon total-memory comparison.
