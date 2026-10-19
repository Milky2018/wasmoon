# Native runtime policy ownership

ISS-635 tracks this migration. GC allocation retry and collection coordination,
exception registries and continuation lifecycle now have MoonBit owners. Native
test layouts live with their implementation. PR #541 supplies platform acceptance
for the exception work (ISS-637). PR #542 supplies Linux/Windows acceptance
for continuation and collection changes and closes test-layout validation.
[Receipts](evidence/runtime-migration-acceptance-2026-10-19/ci.json) distinguish
CI from historical local measurements. This document describes the current
boundary, not completion of the whole epic.

## State and owners

| State or operation | Current owner | Why native storage or control remains |
| --- | --- | --- |
| Wasm objects, object identities, contiguous payload, mark/sweep/compaction | Managed `GCHeapHandle` and native heap implementation | Generated code directly addresses this layout; moving payloads requires refreshing native heap pointers. Logical Store reachability is expanded by MoonBit. |
| Allocation retries and classification of collection failure, quota denial and exhaustion | MoonBit `jit_ffi/gc_heap.mbt::allocate` | Three call-scoped primitives attempt a physical allocation, collect pinned roots, and read the last physical admission result. C has no retry loop. |
| Explicit, live activation, spilled, table and parked roots | Native activation/root registrations plus MoonBit Store visitor | Native stack maps and parked stacks contain machine addresses. The Store visitor traces MoonBit wrappers, exceptions and continuations; its closure exists only during an execution/collection scope. |
| Collection/rollback protocol, visitor ownership and reentry | MoonBit `CollectionState` | Native code copies root spans and mutates physical object storage. A cached precision flag occupies existing padding and is written from MoonBit outside an active collection; no duplicate visitor or phase machine remains in C. |
| Stable exception identity, tag layouts, payload registry, admission and reclamation | MoonBit `ExceptionState` with packed numeric metadata and an RC-retained native callback view | One RC storage owner holds fallible payload buffers and physical root/quota leases. C has no identity registry or reclamation decisions. Handler jump buffers remain a control-transfer primitive. |
| Continuation identities, admission, marks, retirement and sealing | MoonBit `ContinuationState`; an RC bridge retains it | RC physical storage owns bodies, buffers and root/quota leases. Active native cancellation scopes pin bodies directly. Saved machine stacks, platform contexts and stack transfers remain native primitives. |
| Immutable callable metadata | MoonBit registry with RC-retained native array view | Existing example of one logical owner and direct native reads without a second mutable registry. |
| Builtin/import semantics and typed values | MoonBit Store host functions plus the shared hostcall trampoline | Native code transports typed value slots and performs ABI entry/exit; import names do not select duplicate C host implementations. ISS-640 has local validation, with new platform acceptance pending. |
| Tests that allocate private activation layouts | `jit_ffi/testing`, compiled by `jit_ffi` | Test callers retain the `native_test_support` MoonBit facade. No other package allocates a copy of the private activation layout. |

## Synchronous GC allocation call

1. Generated code spills roots according to its safepoint metadata. The native
   bridge resolves the active context, prepares arguments and selects roots.
2. A C stack request borrows the payload and root buffers. Its input format is
   one of struct words, array fill word, array words, struct slots, array fill
   slot or array slots. These formats describe native storage, not a generic
   runtime opcode dispatcher.
3. After the first physical allocation fails, the heap calls a closed MoonBit
   `FuncRef`. It captures no Store, heap or
   closure and creates no RC cycle. The request uses `#external`: it is a
   borrowed C stack address, not an external object that MoonBit can finalize.
4. MoonBit decides whether to collect and retry after that initial failure. The
   existing budgets remain three collections for word inputs and one for full
   slots. A collection failure returns trap 10, independently of allocation
   exhaustion (9), payload quota (25) and identity quota (26).
5. The callback returns either a positive object identity or a negative trap
   code. The native caller releases temporary root/default buffers before
   raising a trap. Neither allocation primitives nor the callback transfer
   control with `longjmp` or park the stack.

The request and its buffers must not escape the synchronous call. Payload
buffers reside in the bridge/caller storage, not inside the movable Wasm heap.
The context retains its heap; collection additionally retains the heap while
invoking a visitor that can retire owners. Canonical runtime type binding is
performed on every successful physical attempt, for word and slot layouts.
Activation root assembly remains in `gc_collect_for_alloc_internal`; its
guard protects native scratch preparation before the heap-wide coordinator
is entered.
The non-callback physical root-copy, sweep and compaction loops capture a
stable native scan span: their writes cannot resize descriptor storage or
change its object count. This removes descriptor reloads forced by potential
C aliasing. The policy pointer is appended to the heap descriptor, preserving
all existing field offsets. Neither change reuses identities or changes which
objects are marked or reclaimed.
A failed visitor receives the existing abort phase before the error returns.

This fixes an existing difference: word allocation helpers used to collapse a
failed collection into allocation exhaustion, while wide helpers reported
missing precise roots. Regression tests now require the precise-root error
and successful subsequent reuse for all six allocation formats.

## Collection and rollback protocol

A native heap retains one MoonBit `CollectionState`; that state holds the
optional Store visitor and a per-heap collection guard, without a direct heap
field. A visitor may indirectly retain the heap through its Store. The visitor
remains bound only during the existing tracing scope,
so Store ownership still relies on balanced `begin_gc_tracing`/`end_gc_tracing`
rather than a permanent RC cycle. Binding and clearing are MoonBit operations.
The public `GCHeapHandle` and `CHeap` interfaces are unchanged.

Normal collection and allocation rollback enter the same closed, synchronous
coordinator with a borrowed native stack request. Both entry paths retain the
heap until the coordinator returns, including when a visitor closes its owning
`CHeap`. A recursive collection on the same heap returns failure without
entering another phase; a different heap has its own guard and may collect.

The coordinator captures one visitor for the complete prepare/finish/abort
protocol. It requests native root seeds, expands typed Store reachability,
decides whether to abort, selects physical sweep/compaction or rollback, then
sweeps exception and continuation owners before visitor completion. Abort
clears native/auxiliary marks and invokes phase 2 on that same captured visitor.
Replacing or clearing a binding in any callback affects the next collection.
The precision flag used by native marking is held stable until this protocol
ends; otherwise an integer resembling a reference could suddenly become a
conservative edge halfway through a precise collection.

The protocol helper is non-raising and returns every outcome to one outer
cleanup point. This avoids a generated per-collection `defer` environment;
release code inspection verifies that the outer coordinator allocates none.
Native root arrays and the visitor's result retain ordinary MoonBit ownership.
The borrowed request is neither RC-managed nor retained past the callback.
No trap or stack switch occurs while a MoonBit coordinator frame is active.

Native code retains root-span copying, stack-map access, physical mark/sweep,
compaction, rollback mutation and accounting primitives. The cached precision
view uses an existing 4-byte gap before the allocation-policy pointer: the
macOS ARM64 native heap descriptor stays 160B, with allocation field offsets
unchanged. There is one additional managed coordinator per heap, not per object
or allocation; JIT context layout is unchanged. Private test helpers receive a
heap made by the managed constructor, so tests do not have a second collector
without its state. The raw physical constructor is now private to its C file.

`gc_heap.mbt` and `gc_collection.mbt` remain in the handle's owning package
because construction and collection methods share private state and the closed
native callback contract; no public registry/layout getters are introduced.
See [collection evidence](evidence/gc-coordination-2026-10-19/README.md) for
before/after failures, negative controls, source hashes, local gates and measured
fast/slow paths. PR #542 completes the platform acceptance under ISS-636.

## Exception registry and native control transfer

`jit_ffi/exceptions.mbt` owns an `Array` of unboxed identity/liveness/mark
records, immutable reference-bearing tag masks, sealing and quota admission.
Identities remain monotonic across reclamation. Lookup first estimates a slot
from monotonic identities, validates the complete live identity, then falls
back to binary search when compaction leaves identity gaps. There is no mutable
lookup cache. Retirement leaves tombstones until batch compaction; sufficiently
sparse storage shrinks, while ordinary surviving collections retain headroom.
Both metadata and physical storage track occupancy rather than historical IDs.

A closed `FuncRef` factory lets standalone contexts create the same state
lazily; Store-bound contexts retain their shared arena. The private runtime
state adds one 8-byte factory pointer on 64-bit targets. The module-shaped layout
seen by generated code is unchanged. Private C test contexts use the managed
constructor rather than a second C-only registry.

The native adapter retains state through MoonBit RC. State owns one RC physical
storage owner and never owns the adapter or a context. That storage owns the
payload buffers and root registrations, retaining each bound quota once. Each
physical record stores accepted charge amounts; close returns those units,
unregisters roots and frees its buffer exactly once. There is no per-snapshot
managed wrapper or RC external object. MoonBit decides admission; failed
physical construction returns before MoonBit rolls back the charge. Appending,
moving, truncating and closing physical slots make no identity or GC decision.
Native control borrows storage only through the retained state, without
inspecting MoonBit's private record layout.

Compiled capture creates a borrowed stack request, invokes the synchronous
MoonBit insertion callback, then checks its returned reference/status. A
failure transfers control only after that callback returns. Throw-by-reference
receives a validated one-based slot from MoonBit, checks physical bounds and
copies the borrowed payload before the native jump. Tag-mask pointers are likewise borrowed from immutable
arrays owned by that registry. Neither pointer escapes these native operations.
The adapter follows the existing typed `FuncRef` conventions; it is not a
runtime opcode dispatcher.

Native root registrations count leases that borrow a heap's exception adapter.
Only the final lease clears that borrowed pointer, including on explicit
snapshot release, collection, clear and last-owner finalization. This permits
another arena to bind safely and prevents an empty heap from retaining a stale
adapter address. Logical marks and sweep decisions live in MoonBit; native
collector calls delegate to that state. Handler chains, spilled machine locals,
active payload copies and setjmp/longjmp remain native control machinery.

The earlier lazy-construction null dereference repair remains covered by the
private failure probe. Added public ownership, quota rollback, last-root and
JIT trap/reuse tests cover the new registry path. See the
[exception evidence](evidence/exception-registry-2026-10-16/README.md), including
negative controls and generated ownership excerpts. The later
[performance investigation](evidence/exception-performance-2026-10-16/README.md)
replaces the initial Map/per-snapshot-owner implementation and separates loop
time from CLI startup; it records both the improvement and residual costs. This is not completion of ISS-635 or ISS-638.

## Continuation lifecycle and cancellation

`ContinuationState` owns one-shot identities, lookup, consumption, GC marks,
heap-specific sweep decisions, quota admission and sealing. Packed numeric
handle rows borrow body addresses only while its RC physical storage owns them.
IDs decrease monotonically and never revive; compaction preserves identity
validation. A found index is consumed directly rather than looked up again by a
linear scan. Ordinary publication retains amortized capacity; explicit reclaim
and clear release excess storage.

The native RC bridge retains state; state owns storage; storage owns RC physical
bodies. State and bodies never retain the bridge or context. Bodies borrow
context-owned immutable type/trampoline/root descriptors and therefore remain
inside the existing execution-context lifetime. These descriptors describe a
machine call and are not a second mutable identity registry. No continuation
factory field was added to the context: the MoonBit type-definition method
creates an arena lazily before invoking the physical descriptor setter.

| Transition | Logical decision | Physical ownership and root visibility |
| --- | --- | --- |
| Create | Admit one pending-work unit, construct, publish a fresh identity | Storage owns a body and its accepted quota lease; parameter roots are registered. Failed construction rolls admission back before returning a trap status. |
| Bind | Consume the old identity, publish a new identity for the same body | Native code copies bound inputs and registers their roots. Failure closes the consumed body before raising a trap. |
| Resume | Consume the identity before executing | A native cancellation scope pins the body. Registrations use active ownership (reference zero); spilled guest roots stay on the physical stack. Scope-allocation failure releases the transferred lease before trapping. |
| Suspend | Publish a new identity after the native fiber returns | Storage retains the parked stack and roots. The resumer disowns its temporary scope pin only after publication succeeds. |
| Switch or forward | Consume the target and publish the source when a matching handler is found | An additional native scope pins the target across forwarding/yield. A matching resumer transfers that pin; cancellation releases nested scopes. Temporary inputs are freed before preparation errors trap. |
| Return, throw or cancel | Consumed identities remain invalid | Native control closes buffers, roots and stack idempotently. Final body release returns its accepted quota once. Exception capture returns a status so the resumer can clean up before throwing. |
| GC or explicit reclaim | Retire unmarked handles for the collecting heap; invalidate metadata before releasing owners | Physical table compaction transfers/drops RC ownership. Active native scope pins remain valid until disowned or cancelled. |
| Clear or last owner | Seal before clearing metadata; no further publication | Close all physical stacks before dropping table owners, since one stack's cancellation scopes can pin another body in that table. Then free the table. |

All callbacks are closed, synchronous `FuncRef`s. Creation requests and output
buffers use borrowed `#external` views and cannot escape. Native entry points
check the returned status and only then trap, yield or switch stacks. Generated
callback adapters contain no ownership operations on these borrowed request
views. No parked stack contains a suspended MoonBit frame.

Root registration now stores an explicit owner kind. Negative continuation
identities contain the exception tag bit, so classifying a lease from that bit
could prematurely detach a still-live exception arena. Exception and
continuation leases now have separate idempotent counters; unregistering the
last lease clears only the matching borrowed adapter. The regression reproduces
the earlier defect independently of the registry migration.

See [continuation evidence](evidence/continuation-lifecycle-2026-10-19/README.md)
for the mixed-root regression, allocation-failure matrices and negative
controls, external suites, ownership review and isolated performance samples.

## Native test ownership and shared headers

The C helpers and platform assembly that inspect private JIT layouts live
under `jit_ffi/testing` without a second package declaration. Their object
files remain separate archive members. Production linking must leave their
unreferenced objects out; the local release symbol check verifies this rather
than assuming it. Their MSVC guest bridges remain a separate generated object,
so production bridge references do not pull test targets into an application.
The MoonBit facade keeps its original package and imports.

Remaining cross-package C headers are small native contracts: the callable
registry view, Windows handle operations, Windows filesystem primitives and
inline path operations. These are not copies of JIT activation layouts. Their
actual transitive includes still require compiler dependency discovery;
relocating tests does not solve ISS-634 or justify flattening/inlining every
header. The installed stable toolchain remains unchanged.

## Verification limits

See [local evidence](evidence/native-runtime-policy-2026-10-16/README.md).
Local macOS ASan/UBSan is not Linux leak detection or Windows compiler
acceptance. ISS-637 is closed with the accepted PR #541 CI receipts and measured
performance investigation. ISS-636, ISS-638 and ISS-639 are closed with
PR #542 acceptance and a fresh
macOS release archive/symbol check. Both Windows compilers execute the actual
MASM bridges and native tests; no Windows release symbol audit is claimed.
Historical pending notes in local measurement receipts describe their original
state and are not relabeled as CI evidence.

The old C prepare/finish/abort protocol and visitor storage have been removed.
The remaining review concerns semantic type checking and continuation
handler/forwarding decisions still interleaved with native control primitives.
Native stack-map traversal, physical payload
scans, fiber/context assembly, ABI entry points and raw OS/buffer operations
remain machine/storage mechanisms. Their presence alone is not an outstanding
instruction to translate every C line.
ISS-634's upstream build-dependency fixes and ISS-640's builtin argument-routing
bug are separate work. The installed stable toolchain is unchanged.
