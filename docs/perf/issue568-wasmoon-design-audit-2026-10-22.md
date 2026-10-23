# Wasmoon GC access and root pipeline audit for #568

## Scope and evidence

This is a read-only source audit of Wasmoon
`c7e407d5686a21dde271a240ca6f5b9a8f20352e`, prepared before another optimization.
No compiler/runtime source was changed, and no build, timing, profiling or CI
run was performed for this note. The parent investigation owns the same-loop IR,
machine-code and engine measurements. The static paths below explain mechanisms;
they do not assign percentages of the remaining performance gap.

Source references are repository-relative paths and one-based lines at that
revision. The workload source is the separate Core checkout's
`internal/strconv/strconv_decimal.mbt`: `right_shift` starts at 373 and
`left_shift` at 520. Its revision/artifact identity must be checked by the
measurement owner; a working checkout alone is not artifact provenance.

## Findings that affect the design decision

1. The current access improvements are useful, but the optimizer cannot reason
   uniformly about their semantic operations. Generic MilkIR classifies every
   extension as unknown. Wasm-specific read forwarding, checked hoisting,
   first-use memoization and native physical-view planning compensate in four
   places. This is a concrete maintenance and optimization limitation, not proof
   that their measured speedups are invalid.
2. A stable logical GC reference, a cached field value and a borrowed physical
   payload address are different facts. A moving collection can preserve the
   first and invalidate the third. An aliasing store can preserve the address
   and invalidate the field value. A replacement design needs those differences;
   replacing every list by one `safe` boolean would be incorrect.
3. The native reference encoding is a stable identity, not a heap pointer or
   byte offset. Even typed fields require an identity-page lookup to reach their
   payload. Successful numeric-array projection amortizes that lookup, but
   scalar struct operations still call dynamically checked C accessors. Removing
   those accessors needs an actual physical-layout contract, not just a module
   type number.
4. Current root scopes already reuse their allocations. Their remaining cost is
   generated stack stores, C push/pop calls and a copy into the reusable scope.
   Allocation maps coexist with those scopes; current allocation maps are not a
   replacement stack walker for all suspended caller frames.
5. Root discovery spans Store-managed values, native heap edges, exception and
   continuation arenas, active reentrant activations and parked registrations.
   These are real distinct lifetimes. A redesign can replace transport and
   duplication, but cannot delete one category because the hot loop does not
   exercise it.

## The production chain

### Frontend and semantic type information

The CLI translates a function body, optionally canonicalizes NaNs, then calls
the Wasm optimizer (`modules/wasmoon/cmd/wasmoon/commands/run.mbt:1979`, `2015`).
The structured frontend translates `struct.get` using the field's IR type and
the declared type/field indices, and `array.get` using the element IR type
(`modules/wasm_milkir/frontend/ir/translator/instr.mbt:1083`, `1170`). Packed
array accesses retain their byte-width opcode (`1184`, `1197`).

Scalar kinds remain distinct, but concrete GC reference subtyping is not a
native SSA type: the frontend maps non-function/non-extern reference forms to
MilkIR `Ref` (`modules/wasm_milkir/frontend/lower.mbt:2`). Concrete contracts
remain in Wasm extension indices and `WasmValidationContext`. Therefore a `Ref`
result alone cannot authorize a statically laid-out struct/array load.

### The current optimizer sequence

`modules/wasm_milkir/optimize/optimize.mbt:8` verifies contextual contracts and
runs this sequence:

1. Short scalar integer-call inlining.
2. Extended-basic-block checked GC read forwarding.
3. Generic optimization.
4. Private one-field integer struct promotion.
5. Checked loop GC-read hoisting.
6. Conditional forwarding and another generic optimization.
7. First-use loop GC-read memoization, then another generic optimization.

This ordering is material. Private promotion removes writes that previously
invalidated read facts, so forwarding runs again (`36`). Memoization rewrites CFG
and inserts value/ready loop parameters, requiring another generic cleanup.

`forward_gc_reads` propagates facts only down one already-known predecessor,
keys by canonical reference/type/field/mode, and kills a written field across
all reference identities/types (`gc_reads.mbt:42`, `94`). That conservative
alias rule correctly avoids assuming two SSA references denote two objects.

`hoist_checked_gc_reads` requires a prior successful check and no field-index
write in the loop (`loop_reads.mbt:54`, `109`). Its logical proof explicitly
allows an allocation to preserve an already-established non-null fact, without
claiming an address remains stable (`75`). It currently rejects all calls,
allocations and polls inside the loop (`148`).

`cache_loop_gc_reads` preserves the first dynamic query/trap, then carries its
value and ready flag through all loop blocks (`loop_values.mbt:60`, `138`). It
handles at most eight candidates through repeated CFG rebuilds (`202`). Its
purpose differs from ordinary LICM: an unexecuted zero-trip/conditional load
must not introduce a null trap. Its CFG restructuring is replaceable only if
the new representation supplies an equivalent non-speculative optimization.

Private integer struct promotion is not a general escape analysis: it admits
only entry allocations, field zero, integer initial values and direct uses;
copies, phis, calls and returns reject the candidate, and the allocation itself
remains (`local_structs.mbt:20`).

### Native physical access planning and emission

Wasmoon opts into explicit heap fields and numeric array regions in
`modules/wasmoon_jit/native_wasm_lower.mbt:23`, `76`. Both target pipelines
stream target-neutral lowering directly into their target lowering sessions
(`166`, `216`; the AArch64 counterpart starts at `260`). They do not run a
general GVN/LICM pass over a complete lowered native-memory graph afterward.

The array planner is a second analysis after the semantic optimizer:

- Eligible storage is packed 8/16 or scalar 32/64; references and v128 are
  excluded (`modules/wasm_milkir/native/array_access.mbt:39`).
- Ordinary regions follow emitted single-predecessor edges, cache source SSA
  identity plus width, and remove one-use regions (`63`).
- Loop regions require a unique earlier-emitted preheader and every cycle
  instruction to satisfy `array_region_local` (`array_regions.mbt:55`).
- A produced reference-valued `struct.get`, an executed length query, or a
  matching element access can create the view (`array_regions.mbt:22`, `36`).
- A separate verifier rechecks origins, side entries, whole-loop effects,
  preheader suffix and identity/width (`123`, `184`). Failure removes the plan,
  selecting checked helpers (`native/lower.mbt:1595`).

The physical planner's emission-order restriction is an implementation
constraint of streaming native SSA construction; it is not a WebAssembly
semantic requirement. A whole-function verified projection plan can remove
that restriction only if lowering can represent its cross-block SSA values
without referring to results not yet emitted.

`prepare_array_view` loads the mutable heap from vmctx, calls
`GcArrayDataHeap(heap, ref, width)`, and branches to load length or supply zero
(`array_access.mbt:122`). Each element use has an unsigned bounds branch;
success emits native `Load`/`Store`, while failure invokes the checked helper
(`168`, `189`, `270`). No element value is cached, so aliasing element writes
remain visible. A different view width has a different proof.

The C projection is total: absent heap/ref, verification mode, invalid/dead
object, wrong kind, incompatible stride or any reference field returns NULL
(`modules/wasmoon_runtime/native/ffi/gc_ops.c:1034`). This is why preparing a
nullable produced field in a zero-trip loop does not introduce a trap. It
validates the actual immutable physical descriptor rather than assuming a
module-local type number equals a physical layout.

### Layout and access cost below the IR

Guest heap words encode `(one-based identity << 1)`; payload resolution shifts
the word and resolves the identity page before adding `heap->data`
(`gc_ops.c:11`; `gc_access.h:10`). The 16-byte object header contains kind,
size, a compact type field and reserved metadata. Physical layout ID is stored
in the upper reserved word; arrays have length at payload+0 and data at
payload+16 (`gc_heap.h:64`, `94`, `195`).

Typed immutable layouts have actual per-field offset/width/reference flags,
with compact scalar fields. Untyped compatibility objects use 16-byte slots
(`gc_heap.h:108`; `gc_access.h:58`, `103`). Identities are never recycled by GC;
sparse pages map them to payload offsets and runtime types, and `live_objects`
provides a traversal independent of the historical identity high-water mark
(`gc_heap.h:116`). Changing identity encoding is therefore a lifetime/API
change, not a local instruction-selection optimization.

Scalar `gc_struct_get_heap_impl` checks heap/ref and calls the shared checked
accessor (`gc_ops.c:1000`). That accessor resolves identity, field count,
physical descriptor, width switch and load (`gc_access.h:58`). Explicit heap
helpers remove TLS resolution for these accesses; claiming every residual
helper pays TLS would be wrong. The old wrappers still resolve TLS for legacy
callers (`gc_ops.c:15`, `376`, `418`).

Reference stores call the existing write barrier; numeric array projection
excludes references (`gc_access.h:73`, `120`; `gc_ops.c:1050`). Direct numeric
loads/stores therefore do not justify removing reference barriers or directly
lowering reference stores without a collector contract.

## Why “unify the effects” is insufficient by itself

Generic optimizer `OpcodeSemantics` currently has memory read/write/unknown,
may-trap and other-observable-effect fields. Calls are unknown; **all dialect
extensions are unknown**
(`modules/milkir/optimize/internal/analysis/effects.mbt:10`, `179`). Generic
LICM refuses trapping/effectful operations (`modules/milkir/optimize/loops.mbt:70`).

The separate Wasm rules currently know facts that generic analysis cannot
express:

| Fact | Invalidated by | Not necessarily invalidated by |
| --- | --- | --- |
| Logical handle remains non-null | substitution/invalid entry, not moving GC itself | successful allocation and object relocation |
| Cached struct field value | aliasing write to that location, unknown reentry | numeric array element write |
| Array length | destroying/replacing the object identity or invalid entry | array element write; arrays cannot resize |
| Physical payload pointer | collection, heap growth/rebind, reentry that can do these | an in-bounds scalar element write |
| Root lifetime | end of its last use after safepoints/suspension/escape | merely leaving the immediate lexical helper call |

`gc_loop_local` admits bulk array operations while `array_region_local` does
not (`loop_reads.mbt:4`; `native/array_access.mbt:13`). This difference is not
automatically a bug or redundant text: logical field invariance and a raw
pointer borrow have different requirements. Raw memory writes end physical
regions because the current IR lacks a proved alias-domain distinction.

A replacement should give each semantic operation a structured, conservative
contract: read/write domain and location, possible trap, allocation/collection,
embedding reentry, heap-base replacement and suspension. Unknown extensions and
imports must remain unknown. These fields must be owned with opcode semantics,
not rediscovered separately by each pass or inferred only from the C symbol's
spelling. Generic optimizer consumers need an extension contract callback or a
lowered representation with these semantics; changing a Wasm-only table does
not automatically teach generic GVN or LICM anything.

The independent verifier should verify dominance, borrow epochs, control and
type/layout compatibility from the resulting plan. It should not merely rerun
the planner or trust an optimizer-written `safe` flag. Sharing opcode semantic
classification is reasonable, but the classification itself becomes trusted
compiler code and needs table completeness/negative-effect regressions.

## Root transport, safepoints and execution lifetimes

### Generated root transport

Generic native lowering computes backwards live GC references for every
instruction (`modules/milkir/native/lower.mbt:773`). The instruction adapter
passes that metadata to root-bearing calls; non-safepoint C accessors explicitly
use calls without roots (`native/adapter/context.mbt:201`, `221`;
`modules/wasm_milkir/native/lower.mbt:308`, `459`). Thus direct struct accessor
cost and root push/pop cost must be counted separately.

Wasmoon installs `CallerRootScopeAbi` plus hidden allocation safepoints for
three allocation helpers (`modules/wasmoon_jit/native_wasm_lower.mbt:86`, `104`).
`DirectBuilder` emits a reusable maximum-size stack object, stores live reference
words into it, calls the push helper, emits the actual call, then calls pop
(`modules/vcode/native_lowering/protocol.mbt:571`). Hidden allocation maps add
safepoint/function IDs and argument-root metadata (`520`).

The runtime push reuses scope objects and growable buffers, but still copies
the words; pop returns a scope to the free list
(`modules/wasmoon_runtime/native/ffi/jit_context.c:466`). “Billions of allocations
remain in root registration” is an outdated description after buffer reuse.
There can still be substantial per-call stores, calls, copy, register-clobber
and list costs, which require current dynamic counts and machine-code evidence.

The allocation selector validates a v2 map, finds the helper's safepoint and
selects roots from the allocation operand buffer (`gc_ops.c:199`). This is not
equivalent to unwinding all native caller frames by return PC. It cannot by
itself replace their root scopes.

It also linearly walks variable-size map records to find the safepoint, then
allocates a fresh selected-root array when there are nonzero precise roots
(`gc_ops.c:247`, `280`). That is a separate remaining allocation/copy mechanism
from the already-reused caller scopes. Its invocation rate and importance need
dynamic evidence; the source alone does not establish billions of calls.

### Root consumers that must survive redesign

- Active activation roots comprise root scopes, exception state, spilled locals
  and scratch, filtered by actual heap identity. Reentrant outer activations
  remain discoverable even while their contexts are detached
  (`native/ffi/trap.c:127`, `189`, `204`).
- Parking copies that activation root set into a heap registration and rejects
  incomplete copies (`trap.c:222`). Arena-owned payload registrations are edges,
  not independent roots. Execution-root enumeration includes active roots and
  unowned parked/input registrations (`gc_heap.c:430`).
- Native allocation collection merges helper operands, scratch, caller scopes,
  exceptions, spilled locals and table roots, then marks active roots
  (`jit_context.c:700`). Collection seeds also enumerate execution roots
  (`gc_heap.c:459`). The same root can therefore reach tracing more than once;
  this is a simplification opportunity only after each path's ownership and
  failure behavior is made explicit.
- Store tracing joins globals/tables/elements/pinned values, native graph
  expansion, wrapped extern references, exceptions and continuations
  (`runtime/gc_tracing.mbt:23`). Native graph expansion uses a trace handle and
  converts discovered typed words back to the shared worklist
  (`runtime/gc_tracing_native.mbt:162`).
- Transaction exception rollback deliberately runs after resource rollback but
  before heap rollback. Managed payload records must remain until the complete
  logical/native graph is found. Incomplete execution/payload discovery aborts
  reclamation; escaped exceptions keep identity and quota
  (`runtime/native_exception.mbt:295`). A root-transport rewrite must preserve
  this shared enumeration, not just ordinary allocation GC.

### Entry contracts are not yet one closed world

The rooted `Function` interface binds Store/instance/lifetime and validates
arguments/results (`modules/wasmoon_runtime/executor/function.mbt:1`, `65`,
`117`). JIT external sync and resumable entry explicitly call
`validate_call_arguments` (`modules/wasmoon/wast/jit/call.mbt:303`, `412`).
Raw values below that seam remain Store-local integration values; a bare
integer reference cannot prove Store provenance by itself.

The hostcall dispatcher has a separate path: host functions return values,
then results are length-checked and encoded using the signature
(`wast/jit/support.mbt:1221`, `1409`). This source read did not establish that
every host-return concrete reference contract has the same validation as the
rooted interface. It is **not** a reproduced new bug in this audit. It is a
prerequisite to investigate before using module-local static layout assumptions
at all JIT entries. Imported function signatures and indexed reference types
must be resolved in the correct owner/caller schema; checking against whichever
instance is convenient can reject valid cross-module subtypes.

## Replacement architecture and deletion table

The narrow coherent design is one **Wasm GC lowering module** before streaming
target selection. Its interface consumes context-validated semantic GC
operations and a physical-layout adapter, and produces ordinary scalar/memory
operations plus explicit checks, barriers, relocation points and safepoint
contracts. Logical references remain `GcRef` values; projected addresses are
borrowed values tied to a heap epoch. This avoids building a second full native
optimizer merely to undo opaque helper calls. Layout resolution remains an
embedding adapter; reusable compiler packages must not import Wasmoon.

The optimizer must see semantic reads and their location/effect information
before they expand into per-access branch diamonds. If it only sees those
diamonds during streaming selection, generic CSE/LICM arrives too late. A
single typed projection should dominate its uses; a relocation/reentry barrier
requires re-projection, while an alias write invalidates affected values rather
than the payload address. Checked null/bounds operations stay ordered unless
redundancy or safe speculation is actually proved.

| Existing mechanism | Intended action | Prerequisite for deletion | Required guarantees |
| --- | --- | --- | --- |
| `gc_reads.mbt` bespoke checked-read cache | Replace by location-aware value numbering on semantic GC loads | Generic optimization consumes extension memory domains and trap/check facts; alias kill handles distinct SSA aliases and subtypes | Field writes kill all potentially aliasing reads; array data does not alias struct fields; no removed first trap |
| `loop_reads.mbt` checked-object walk and dedicated hoister | Delete after common dominance/check facts plus loop invariant-load analysis handle its cases | Separate logical validity from physical heap epoch; preserve prior check or establish must-execute proof | Null/zero-trip/conditional traps unchanged; allocation does not unnecessarily erase stable logical facts |
| `loop_values.mbt` ready/value CFG memoization | Prefer deletion after ordinary redundant-load elimination plus safe projection removes its hot uses; retain temporarily if semantic tests lose coverage | Equivalent first-execution behavior for nullable/conditional reads, not merely LICM of trapping loads | First query remains conditional; phi arguments, nested loops and parallel copies remain correct; no artificial loop state needed in the replacement |
| `native/array_access.mbt` and `array_regions.mbt` opcode/producer pattern planner | Replace with explicit projection/check/use SSA and epoch verification | Lowered representation supports dominance across blocks without streaming emission-order dependence, typed physical descriptors and mandatory verification | No payload address crosses allocation/reentry/poll/heap rebind; aliases observe writes; width/kind and compatibility layouts validated |
| Duplicate `gc_loop_local`, `array_region_local`, cache invalidation matches | Delete duplicated classification, not distinct logical/physical predicates | One conservative semantic effect description, with independent queries for value invalidation and address invalidation | Unknown op/import always invalidates what cannot be proved; raw stores remain barriers unless alias domain is established |
| JIT scalar struct/array get/set C calls for proved typed objects | Remove from the optimized guest path | Physical layout adapter yields canonical field offsets/stride and actual-kind contract; reference stores have explicit collector barrier lowering | Host/raw/wide layouts still work through compatibility adapter; identical null/bounds errors; no wrong-type memory access |
| `GcArrayDataHeap` per-object C projection | Remove from the normal guest path only after lowered identity/layout resolution can be shared directly | Stable identity lookup and physical layout query are represented/optimized in compiler IR, or a deliberately changed guest-ref contract replaces them | Do not infer physical width from module type ID; keep verification mode and raw host values safe |
| `CallerRootScopeAbi` call-site stack stores + C push/copy/pop | Replace after a real frame-root design is complete; not an immediate deletion | Either a function-lifetime linked root frame with safepoint slot maps, or return-PC stack maps plus reliable active/parked frame walking; all targets and unwinding paths supported | Live roots survive internal/host calls, nested reentry, suspension, cancel, tail calls, trap unwinding and transaction rollback; roots do not retain dead graphs indefinitely |
| Allocation operand map parsing/linear map search | Replace by compiled direct descriptor/index access as part of root ABI redesign | Descriptor ownership/versioning shared with artifact generation and loader; malformed artifacts still rejected | Exact allocation operand roots preserved, including references only live as allocation inputs; no silent conservative fallthrough |
| Multiple active-root mark/copy/seed transports | Merge behind one complete enumeration interface where possible | Consumers distinguish root sets from arena edges, read-only liveness from marking, failure from empty results | Same-heap active/detached/parked roots and nested exception/continuation closure; incomplete discovery never authorizes reclamation |
| Private integer-box promotion | Keep initially; replace only with measured general escape/scalar-replacement work | Correct escape/alias analysis across copies, phis and calls; allocation/quota/trap contract decided explicitly | Existing allocation observability retained unless the product intentionally changes it; scalar replacement does not silently remove quota failures |
| Legacy TLS wrappers/shared host checked accessors | Keep as an adapter until all public/low-level callers migrate | Caller inventory and public compatibility policy; optimized code no longer links them unnecessarily | Standalone native helpers, raw host slots, debug verification and wasm target semantics remain supported |
| Stable non-recycled identity pages | Do not delete as a “GC access cleanup” | Separate reference-representation design with host rooting, stale-handle detection, cross-Store identity, movable heap and artifact ABI decisions | Old raw handles never silently designate a new object; lifetime and quota semantics stay explicit |

## Sequencing and acceptance before implementation

1. Finish the cross-engine same-loop comparison first. Count instructions,
   helper calls, root stores/copies, branches and spills for the identical loop;
   separate startup/compilation from invocation. This audit does not establish
   whether struct helpers, root scopes, allocation or arithmetic dominates the
   remaining full-property time.
2. Define one operation/effect/layout contract and prove it can express both
   current passes' negative cases and direct numeric accesses. No performance
   claim should depend on weakening the raw-value or safepoint contract.
3. Replace logical-read passes and physical projection planning as one reviewed
   change, migrating behavioral tests rather than preserving filename/IR-shape
   tests for deleted mechanisms. Keep independently forged-plan verification
   tests at the new projection seam.
4. Redesign root transport as a separate change, driven by measured caller/root
   cost. Establish active, parked and reentrant enumeration before removing the
   old copy scopes. Allocation maps alone are insufficient acceptance.
5. Treat new reference encoding or collector strategy as a separate architecture
   decision, supported by measured benefits after compiler/root simplification.
   The user permits broad deletion, but it does not make a simultaneous heap,
   ABI, optimizer and lifetime rewrite easier to validate.

Required regression dimensions are the existing null/bounds/zero-trip/nullable
cases; subtype and wrong-kind entry; all scalar widths and compatibility wide
slots; aliasing writes; allocation and moving GC between uses; host reentry and
heap replacement; active and parked nested exception graphs; continuation
resume/cancel; quota rollback/reuse; internal/direct/indirect/tail calls with
mixed scalar/vector hidden results; artifact revision rejection; native+wasm
Core and Component parity. Actual ARM64 execution does not replace actual x64
execution. Benchmark medians alone do not replace those lifetime guarantees.
