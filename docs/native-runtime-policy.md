# Native runtime policy ownership

ISS-635 tracks this migration. The GC allocation slice and private native test
layout move are implemented locally. Exception registry ownership has also
moved to MoonBit; its platform acceptance and further performance work remain
open. Continuation registry migration is still unfinished. This document describes that intermediate state,
not a completed removal of runtime policy from C.

## State and owners

| State or operation | Current owner | Why native storage or control remains |
| --- | --- | --- |
| Wasm objects, object identities, contiguous payload, mark/sweep/compaction | Managed `GCHeapHandle` and native heap implementation | Generated code directly addresses this layout; moving payloads requires refreshing native heap pointers. Logical Store reachability is expanded by MoonBit. |
| Allocation retries and classification of collection failure, quota denial and exhaustion | MoonBit `jit_ffi/gc_heap.mbt::allocate` | Three call-scoped primitives attempt a physical allocation, collect pinned roots, and read the last physical admission result. C has no retry loop. |
| Explicit, live activation, spilled, table and parked roots | Native activation/root registrations plus MoonBit Store visitor | Native stack maps and parked stacks contain machine addresses. The Store visitor traces MoonBit wrappers, exceptions and continuations; its closure exists only during an execution/collection scope. |
| Stable exception identity, tag layouts, payload registry, admission and reclamation | MoonBit `ExceptionState` with packed numeric metadata and an RC-retained native callback view | One RC storage owner holds fallible payload buffers and physical root/quota leases. C has no identity registry or reclamation decisions. Handler jump buffers remain a control-transfer primitive. |
| Continuation handle registry, state transitions and cancellation | C continuation arena plus MoonBit execution adapters | Still to migrate in ISS-638. Saved machine stacks, platform contexts and stack switching remain native primitives. |
| Immutable callable metadata | MoonBit registry with RC-retained native array view | Existing example of one logical owner and direct native reads without a second mutable registry. |
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
Reentry protection and root merging remain in `gc_collect_for_alloc_internal`.
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
acceptance. ISS-636 and ISS-639 remain in progress until the outstanding
acceptance criteria are met. ISS-637's registry migration is implemented locally
but remains in progress for platform acceptance and measured exception-heavy
overhead. ISS-638 remains open.
