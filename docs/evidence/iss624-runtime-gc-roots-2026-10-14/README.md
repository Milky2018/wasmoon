# ISS-624: Runtime roots and operational reclamation

This review and fix starts from `02d5d093c8c779f62409497c10c0a56e9e72678e`.
Results below describe the uncommitted implementation on
`milky/reclaim-runtime-gc-roots`, on macOS ARM64 with MoonBit stable
0.1.20261012. They are local results, not cross-platform CI acceptance.

The original [independent reproduction](../runtime-quality-2026-10-14/README.md)
remains unchanged. Its interpreter loop externalizes and discards 1000 structs.

| Observation | Before | After |
| --- | ---: | ---: |
| Wrapper entries before collection | 1000 | 1000 |
| Reachable object roots | 1000 | 0 |
| Objects reclaimed by forced collection | 0 | 1000 |
| Live objects after collection | 1000 | 0 |

The shared regression fixtures additionally verify that wrapper entries and
oversized wrapper buckets return to baseline after collection. Ordinary tests
and the sanitizer runner use the same fixture source files:

- [runtime root fixtures](../../../modules/wasmoon/sanitizer_testsuite/runtime_gc_roots_test.mbt)
- [native root fixtures](../../../modules/wasmoon/sanitizer_testsuite/native_gc_roots_test.mbt)

## Ownership and root inventory

A guest reference encoded in a MoonBit `Value` is an identifier, not an RC-owned
guest object. RC manages the MoonBit containers, C handles, callback closures,
and fibers; guest GC traces the identifiers. Both mechanisms must agree on
which owner is live.

| Family | Owner and required retention | Release event and disposition |
| --- | --- | --- |
| Externalized GC references | A wrapper identifier connects a live externref to a struct, array, or i31. Globals, tables, fields, exceptions, segments, parked state, and explicit host leases can own that identifier. | Trace only wrappers reached from those roots. Sweep unreachable map entries, compact excessive bucket capacity, and never reuse identifiers. The original permanent-root defect is fixed. |
| Exception payloads and native mirrors | Live exnrefs own immutable payload snapshots. Native and interpreter identities map to the same exception while it is live. | Trace payload edges transitively. Native exception tokens use a distinct tag, avoiding confusion with i31 and object references. Sweep snapshots, payload buffers, root registrations, and mirror mappings. Compact live native entries without changing their identifiers. Deep translation uses worklists. |
| Guest continuations | A reachable one-shot handle owns bound arguments and paused execution. An active resumer or a host that takes a body temporarily owns its roots. | Stored bodies delegate their leases to guest reachability. Taking a body restores host protection; run/cancel releases it. Rebinding transfers leases and deduplicates roots. GC cancels discarded bodies. Native root slots and parked fiber slots belong conditionally to their handle; consumed rows and unborrowed retired identity records are reclaimed. Cancellation scopes keep borrowed records alive until their own release. |
| Interpreter embedding pauses and asynchronous host calls | The embedding explicitly owns a suspended call or pending/completed host task, rather than a guest continuation value. Completed reference results remain rooted until incorporated into the executor. | Existing root leases and cancellation registrations remain unconditional while owned. Resume, completion, cancellation, transaction cleanup, and terminal Store close release them. New fixtures cover externalized exception results on both heaps, including unconsumed completed tasks. |
| Root leases | An active lease snapshots host-visible values and protects their transitive graph. | Release is idempotent, removes the registry entry, and detaches the lease's Store reference. Guest-owned leases are traced through their continuation instead of acting as permanent roots. Taken bodies require run, cancel, or transfer. Raw host Values still require a lease or `additional_roots`. |
| Globals, tables, and native active frames | These are roots while their Store or invocation is live. Native global callbacks must decode exnref and contref as well as object references. Table synchronization and active native root scopes cover guest updates and reentry. | Globals/tables remain Store-owned. Invocation completion, trap, or cancellation removes temporary frame roots. Native exception payload layouts and paired spill buffers keep scalar/SIMD words out of the root set. Existing host GC and reentry fixtures remain enabled. |
| Element segments | Undropped passive segments own evaluated values. Active segments transfer values to their destination table; declarative segments have no runtime contents. | Drop clears evaluated arrays and their backing slots. Native and interpreter segments share instance-local dropped bits, so native `elem.drop` immediately stops Store root tracing and affects interpreter reads. Active/declarative contents are retired as well. |
| Data segments and original module bytes | Native contexts retain RC-managed segment bytes; instances and artifacts can also retain their original parsed module for compilation and execution metadata. Bytes do not contain guest GC references. | Native `data.drop` releases the context's segment payload and updates shared dropped bits. Interpreter/native availability is consistent. Original parsed module bytes intentionally follow their owner lifetime; dropping a runtime segment does not mutate a shared module or artifact. No additional guest root defect was found in data bytes. |
| Instances, function/tag addresses, and executable owners | Successful registrations have stable Store-local addresses. Functions can escape into imported tables. A failed start in the low-level Core API is not automatically a transactional unlink of all Store allocations. | Retain registered entities until Store close unless an explicit instantiation transaction owns them. Transaction rollback restores roots, removes mappings and auxiliary entries, and releases truncated backing slots. Tests exercise explicit rollback after a start trap; existing imported-side-effect rollback tests remain enabled. This change does not impose unsafe automatic rollback on the Core API. |
| Type identities and native callable metadata | Canonical type graphs and callable owners must remain available to references from multiple modules. | Type representatives now retain type/recursive-group graphs rather than complete instances and segments. Object layouts are recorded at allocation, including constant expressions before an instance exists. Rollback removes instance mapping entries. Shared native callable registries hold metadata without Store callbacks. Legacy explicit callable views retain their callbacks until Store close under their existing registration contract. |
| Native GC visitor and callback cycles | A native collection temporarily needs the Store's typed root visitor. A permanent C-owned closure capturing Store would create a Store/heap cycle. | Bind the visitor only during explicit collection or managed native execution; nested scopes balance releases on return, trap, and suspension. A parked call keeps its existing native root registrations, and the next Store collection installs a fresh visitor. The collector retains its heap across callbacks that can retire the Store. No permanent visitor is installed by creating a Store. |
| Native object identity metadata and high-water capacity | Object offsets/type IDs use monotonic native indices to reject stale identifiers; canonical type graphs, original code, and shared artifacts are also required ownership. | Guest payloads and auxiliary records are reclaimed. Native object-table tombstones and some allocation capacity intentionally retain identity/high-water metadata until Store close. This is a resource-accounting/admission-policy concern tracked by ISS-627, not a claim of constant RSS. Protected public host handles remain ISS-626. |

## Tracing protocol and failure behavior

The Store builds one iterative transitive graph across heap objects, wrapped
externrefs, exceptions, and continuations. Native object fields use the type
layout captured for their allocation; scalar slots are not scanned as references.
Untyped low-level CHeap allocations retain their conservative raw-word contract.
Use `Store::collect_garbage` for Store-managed collection.

The native visitor receives active/parked roots and premarked roots, expands them
before sweep, and retires auxiliary owners after sweep. If an edge cannot be
translated, collection aborts without freeing live objects; marks and temporary
trace state are reset. Nested collection is rejected while the outer collection
is active. Cancellation candidates are detached before user callbacks run, so a
callback-created successor is not swept by the old candidate set.

C callbacks use `FuncRef` trampolines and explicit RC ownership. Borrowed arena
links are detached before the final owning root registration drops its heap.
Native continuation resource scopes separately count their identity borrows.
This preserves cancellation cleanup without retaining every historical body.

The public diagnostic registries `Store.exns` and `Store.wrapped_externs` are now
maps of live, non-reused identifiers. `GuestContinuationBody` construction goes
through its constructor so the engine can carry root/lease metadata. Instance
dropped arrays are fixed-size shared boolean arrays; their C ABI uses byte
storage. Generated interfaces are produced by `moon info`.

## Validation

The local gates include strict native checking with warning 73, formatting,
generated interfaces, the full native test suite, module dependency boundaries,
and ASan/UBSan with deliberate instrumented failures as positive controls.

External validation uses rebuilt CLI binaries. Core WAST runs both engines;
the GC subset also runs with `WASMOON_GC_HEAP_CAPACITY=65536` to exercise collection
pressure. Component stable-0.2 and async-0.3 run through the pinned snapshot.

The recorded sanitizer closure uses the system allocator and instruments C
stubs and the fixture package. It excludes MoonBit runtime objects and emitted
JIT machine code. macOS ASan/UBSan success does **not** establish Linux LSan
acceptance. The local Docker daemon is unavailable. Linux leak detection and
Windows Clang/MSVC acceptance therefore remain pending CI, and ISS-624 remains
in progress until that evidence is obtained.

See `validation.json` for commands, counts, source identity, and binary hashes.
