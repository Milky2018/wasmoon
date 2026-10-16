# Native runtime policy ownership

ISS-635 tracks this migration. The GC allocation slice and private native test
layout move are implemented locally; exception and continuation registry
migration is still unfinished. This document describes that intermediate state,
not a completed removal of runtime policy from C.

## State and owners

| State or operation | Current owner | Why native storage or control remains |
| --- | --- | --- |
| Wasm objects, object identities, contiguous payload, mark/sweep/compaction | Managed `GCHeapHandle` and native heap implementation | Generated code directly addresses this layout; moving payloads requires refreshing native heap pointers. Logical Store reachability is expanded by MoonBit. |
| Allocation retries and classification of collection failure, quota denial and exhaustion | MoonBit `jit_ffi/gc_heap.mbt::allocate` | Three call-scoped primitives attempt a physical allocation, collect pinned roots, and read the last physical admission result. C has no retry loop. |
| Explicit, live activation, spilled, table and parked roots | Native activation/root registrations plus MoonBit Store visitor | Native stack maps and parked stacks contain machine addresses. The Store visitor traces MoonBit wrappers, exceptions and continuations; its closure exists only during an execution/collection scope. |
| Stable exception identity, payload registry and reclamation | C exception arena, with a MoonBit managed owner | Still to migrate in ISS-637. The current C registry is not merely an ABI stub. Native handler jump buffers remain a control-transfer primitive. |
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

## Lazy exception arena failure

Two exception snapshot entry points lazily create an arena and then read its
admission status after insertion fails. If arena creation itself failed, that
status read dereferenced null. The existing private recovery probe now injects
failure at first arena creation in both current-exception and explicit-payload
capture; before the fix it exits with SIGSEGV. Both paths now return the native
out-of-memory trap and allow the same context to work after fault injection
is disabled. This is a safety repair while ISS-637 remains in progress, not a
claim that the exception registry has moved to MoonBit.

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
acceptance criteria are met; ISS-637 remains in progress after a narrow lazy-arena OOM repair; its
registry migration is unfinished. ISS-638 remains open.
