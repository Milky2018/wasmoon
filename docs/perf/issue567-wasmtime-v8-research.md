# Issue 567: Wasmtime and V8 implementation research

This note compares implementation mechanisms with the Wasmoon diagnosis at
`f06da25eca50f4de81552ac6a583e848fcd31d97`. It contains source research, not a new
benchmark or an implemented repair. The earlier Wasmoon measurements remain
separate evidence; they do not establish how much each upstream mechanism would
improve Wasmoon, and individual speedups must not be added together.

## V8 source baseline

V8 sources below are pinned to
[`ce9b602801d929dd00ad4d4369f4ef8cd14e8880`](https://github.com/v8/v8/commit/ce9b602801d929dd00ad4d4369f4ef8cd14e8880),
verified through the official repository commit API on 2026-10-21. This is a
source snapshot, not a tested V8 binary or a claim about the exact configuration
of Chrome. Build flags, architecture, pointer compression, compiler tier and
collector choice affect concrete layouts and execution paths.

V8's WasmGC objects use its managed heap infrastructure, which also serves
JavaScript. Ordinary Wasm structs and arrays are allocated in the young
generation; shared types use shared old space. This is visible in Turboshaft's
`WasmAllocateStruct` and `WasmAllocateArray` lowering. It is a different ownership
and collector environment from Wasmoon's explicit Store/native heap.
[Source: wasm-lowering-reducer.h, lines 519–580](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/compiler/turboshaft/wasm-lowering-reducer.h#L519-L580).

### Executable code is suballocated within owned code spaces

`WasmCodeAllocator::AllocateForCodeInRegion` aligns individual allocations to
`kCodeAlignment` and takes them from `free_code_space_`. If necessary it reserves
another larger virtual-memory range, records ownership in `owned_code_space_`,
and associates it with the `NativeModule`. Only newly covered page ranges are
committed. Thus V8 does not require a separate page-sized virtual-memory mapping
for every small Wasm function. `FreeCode` coalesces freed ranges and decommits
complete free pages; allocator destruction frees its owned module code spaces.
[Allocation](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/wasm/wasm-code-manager.cc#L875-L955),
[reclamation](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/wasm/wasm-code-manager.cc#L958-L998),
[ownership](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/wasm/wasm-code-manager.cc#L670-L688).

Code packing does not mean removing write protection. V8 separately manages
writable JIT allocations and platform permission scopes. On Apple Silicon the
`RwxMemoryWriteScope` contract uses thread-local MAP_JIT/APRR write/execute
switching; Intel PKU provides write protection with different semantics. The
source explicitly says the scope is a no-op on other configurations, so it
would be incorrect to describe that one scope alone as universal W^X.
[Source: code-memory-access.h, lines 68–132](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/common/code-memory-access.h#L68-L132).

**Implication for Wasmoon:** module-owned, bounded code arenas are a concrete
alternative to per-function mappings. Keep function ranges, relocation reach,
unwind/trap registration, code lifetime and permission transitions explicit.
Packing functions may improve locality, but this source does not identify the
TLB/cache/branch-prediction split or quantify a Wasmoon speedup.

V8 also coordinates code publication/replacement across tiers under its module
allocation mutex and retains referenced code before retiring old code. Potentially
dead code goes through engine code-GC bookkeeping. Wasmoon need not reproduce
this full concurrent/lazy/tiering machinery to gain packing: artifact-owned packed
ranges with a clear last-user lifetime can be a smaller first step than a global,
permanent code arena.
[Publication and replacement](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/wasm/wasm-code-manager.cc#L1422-L1554),
[reference retirement](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/wasm/wasm-code-manager.cc#L599-L614).

### Roots are described by safepoint metadata and visited in physical slots

`CodeGenerator::RecordSafepoint` converts the allocator's reference map into
tagged stack-slot metadata. At collection, `WasmFrame::Iterate` looks up code and
its safepoint entry from the frame PC, visits the tagged spill slots, tagged
incoming parameters and fixed instance roots. Its stack-switch handling also
selects the correct outgoing-parameter area across secondary/central stacks.
This is evidence for metadata-driven stack scanning, rather than requiring a
heap-allocated copy of every live reference set at each guest call. It is not a
claim that V8 never allocates handles, spills references or uses wrapper roots.
[Map generation](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/compiler/backend/code-generator.cc#L613-L631),
[frame scanning](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/execution/frames.cc#L1773-L1938).

Suspension does not remove roots: `StackMemory::Iterate` has separate active and
suspended-stack frame iterators. `IterateWasmFXRoots` separately visits the
continuation/function/stack objects and bound reference arguments in its argument
buffer. Its young-generation optimization skips an inactive stack only after
establishing it contains no young pointers; non-young visitors still traverse
the stack. These are explicit lifetime contracts, not a generic linked list of
currently active calls. The WasmFX-specific scan starts with the
`v8_flags.wasm_wasmfx` feature check: its existence in this source snapshot does
not establish enabled-by-default or shipping continuation support, or equivalent
proposal coverage to Wasmtime 49.
[Source: stacks.cc, lines 158–224](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/wasm/stacks.cc#L158-L224).

**Implication for Wasmoon:** first remove repeated system allocation by giving
root-scope storage an execution/fiber lifetime and reusing popped capacity, while
preserving current root semantics. A later PC/stack-map design can avoid some
copying, but must cover parked workers, host reentry, outgoing/return references,
tail calls, exceptions, cancellation and rollback before replacing existing
protection. Recent snapshot-liveness repairs make an active-stack-only design
especially unsafe.

### Objects use type-specific layouts and generated field accesses

`StructTypeBase::InitializeOffsets` uses each field's byte size and alignment,
fills suitable alignment gaps, and preserves offsets for common subtype field
prefixes. References use `kTaggedSize`, whose concrete size depends on the build.
`WasmArray::SizeFor` uses `header + round_up(element_size * length)` rather than
a universal 16-byte element slot. V128 still legitimately needs 16 bytes.
[Struct offsets](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/wasm/struct-types.h#L63-L138),
[reference size](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/wasm/value-type.h#L486-L495),
[array size](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/wasm/wasm-objects-inl.h#L1412-L1438).

Turboshaft lowers array access directly to typed indexed loads/stores with an
element-size scale and the object header offset; reference stores preserve their
required write barriers. Allocation computes the same type-specific sizes.
[Source: wasm-lowering-reducer.h, lines 432–580](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/compiler/turboshaft/wasm-lowering-reducer.h#L432-L580).

**Implication for Wasmoon:** compute one validated layout descriptor per type
and share it between allocation, GC tracing and code generation. Direct field
access can then use that descriptor while retaining null/bounds/type checks.
Do not copy V8 pointer compression, map headers or raw tagged-pointer encoding:
these depend on its cage, heap, barriers and relocation machinery. Wasmoon's
reference identity, interpreter/JIT agreement and moving-GC protocol need their
own consistent contract.

### Allocation has a fast path and policy limits before OS exhaustion

Turboshaft's `MemoryOptimizationReducer::ReduceAllocate` loads the allocation
top and limit, checks space/size, advances top on the fast path, and otherwise
calls the Wasm young/old allocation builtin. It can fold adjacent allocations.
The runtime `MainAllocator::AllocateFastUnaligned` follows the same bounded
linear-allocation-area model. A nursery limit is not the same as an operating
system allocation failure.
[Generated allocation](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/compiler/turboshaft/memory-optimization-reducer.h#L250-L415),
[runtime allocation](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/heap/main-allocator-inl.h#L16-L53).

The slow path consults young-space target capacity and expansion policy; old
allocation can start incremental marking when its allocation limit is reached.
Allocation observers also shorten the inline limit so generated-code allocation
remains accounted for. Runtime allocation retries explicitly collect garbage.
These mechanisms establish policy-driven collection/accounting before waiting
for physical malloc failure; they do not imply collection at every LAB refill.
[Capacity and marking policy](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/heap/main-allocator.cc#L625-L680),
[observer limits](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/heap/main-allocator.cc#L350-L383),
[collection retry](https://github.com/v8/v8/blob/ce9b602801d929dd00ad4d4369f4ef8cd14e8880/src/heap/heap-allocator.cc#L556-L582).

**Implication for Wasmoon:** add an allocation-debt/retained-live-size policy at
existing safe collection points before simply increasing physical capacity.
An earlier full collection can still be slower if roots, identity tables or
dead-object traversal are expensive. Nursery/generational collection additionally
requires write barriers and remembered-set correctness; it is not a threshold
constant change.

### Scope and limits

The workload is a MoonBit regular-expression implementation compiled to Wasm.
V8's JavaScript RegExp engine is not the engine executing that guest algorithm;
its JS-specific regexp JIT is therefore not an explanation or a transferable
fix for this result. The relevant V8 comparisons are Wasm code placement,
compiled WasmGC operations and managed-heap/root protocols.

This review did not execute V8, measure V8-versus-Wasmoon ratios, inspect every
baseline/interpreter path, or establish which collector configuration would run
the benchmark. Wasmoon still needs same-workload, same-platform controls with
correctness/root-protection checks for each proposed optimization.

## Wasmtime source baseline

The comparison uses Wasmtime **49.0.1**, pinned to
[`46c23a87dac1465986a8ad53ba6a7ae49372857b`](https://github.com/bytecodealliance/wasmtime/commit/46c23a87dac1465986a8ad53ba6a7ae49372857b),
also the version used in the preceding benchmark. Collector-specific paths
below describe the copying collector; they do not describe every selectable
Wasmtime collector or establish which collector produced a historical timing.

### An artifact owns code and its associated metadata

`CodeMemory` owns an `MmapVec` containing text and metadata ranges, including
stack maps, traps, exceptions, unwind information and function names. Publication
handles executable permissions and instruction-cache synchronization. Its drop
implementation removes unwind/debug registrations before unmapping the bytes
they reference. Function code can occupy ranges inside the artifact rather than
requiring one mapping per function.
[Source: code_memory.rs](https://github.com/bytecodealliance/wasmtime/blob/46c23a87dac1465986a8ad53ba6a7ae49372857b/crates/wasmtime/src/runtime/code_memory.rs#L23-L75).

This is a closer initial model for Wasmoon than V8's tiered code replacement:
the existing installer already stages the complete artifact, resolves all
function addresses, relocates, protects and publishes transactionally. A packed
layout could preserve that transaction while replacing the per-function mapping
ownership underneath it. Allocation failure, relocation range, code quotas,
cache flush, registration rollback and the last invocation/continuation's
lifetime must remain explicit.
[Wasmoon installer](../../modules/wasmoon_jit/artifact/installer/install.mbt#L420).

### Compiled stack maps include suspended execution, with explicit limits

`trace_wasm_stack_frame` finds the code by PC, looks up the stack map, and adds
the actual mutable reference slots to the collector's roots. Other enumerators
cover globals/tables, embedding roots, instances and the pending exception.
Suspended continuation stacks have their own traversal. This design avoids
requiring per-call heap copies solely to make guest stack references visible.

However, this version explicitly disallows `cont.bind` of GC values because it
lacks the RTTI needed to trace their argument buffers. Wasmoon already supports
native bound/input references, so replacing its enumeration with this version's
enumeration would lose coverage. Pending exceptions and embedding handles also
remain explicit roots; stack maps are only one part of the lifetime protocol.
[Sources: root enumeration and continuation limitation](https://github.com/bytecodealliance/wasmtime/blob/46c23a87dac1465986a8ad53ba6a7ae49372857b/crates/wasmtime/src/runtime/store/gc.rs#L672-L870).

### Typed layout supports direct access and a bounded allocation fast path

`byte_size_of_wasm_ty_in_gc_heap` gives I8/I16 fields 1/2 bytes, I32/F32/reference
fields 4 bytes, I64/F64 fields 8 bytes and V128 fields 16 bytes. Shared layout
helpers compute naturally aligned field offsets and array strides. A collector's
object alignment does not force every field to have that alignment or size.
[Source: GC layouts](https://github.com/bytecodealliance/wasmtime/blob/46c23a87dac1465986a8ad53ba6a7ae49372857b/crates/environ/src/gc.rs#L70-L188).

Cranelift's `translate_struct_get` obtains the field offset and storage type,
checks the reference/address, and emits the corresponding field read. The
copying collector's inline allocation checks aligned size against the active
semi-space's bump limit, advances the pointer and initializes the object. Only
the cold path calls `gc_alloc_raw`; returned references are declared to need
stack-map coverage. These paths rely on that collector's reference encoding and
movement protocol, not just arithmetic on a pointer.
[Field lowering](https://github.com/bytecodealliance/wasmtime/blob/46c23a87dac1465986a8ad53ba6a7ae49372857b/crates/cranelift/src/func_environ/gc.rs#L556-L607),
[copying allocation](https://github.com/bytecodealliance/wasmtime/blob/46c23a87dac1465986a8ad53ba6a7ae49372857b/crates/cranelift/src/func_environ/gc/copying.rs#L97-L219).

### Allocation pressure drives collection versus growth

An allocation failure here can mean that the current GC allocation region is
full, rather than that the operating system refused memory. The retry policy
uses the previous post-GC live size, requested bytes and current capacity. In
the ordinary representable case it prefers collection when predicted usage is
less than half the capacity; otherwise it prefers growth. The two paths retain
bounded retries and fallbacks.
[Retry policy](https://github.com/bytecodealliance/wasmtime/blob/46c23a87dac1465986a8ad53ba6a7ae49372857b/crates/wasmtime/src/runtime/store/gc.rs#L410-L501),
[decision helper](https://github.com/bytecodealliance/wasmtime/blob/46c23a87dac1465986a8ad53ba6a7ae49372857b/crates/wasmtime/src/runtime/store/gc.rs#L1070-L1128).

Wasmoon's current `gc_allocate` returns immediately after a successful physical
allocation, entering its MoonBit policy only on failure. Since its heap can grow
while allocation keeps succeeding, dead temporary objects need not create GC
pressure soon enough. The useful upstream idea is a bounded allocation budget
and live-set-aware growth policy, not a requirement to collect on every refill.
[Wasmoon policy boundary](../../modules/wasmoon_runtime/native/ffi/gc_allocator.c#L59).

## Recommended Wasmoon sequence

The following are proposed work items, not implemented fixes. They target
different measured costs and are not additive speedup estimates.

| Order | Change | Scope and verification |
| --- | --- | --- |
| 1 | Pack function code within an artifact-owned mapping or bounded chunks. | Retain staged installation, symbolic relocations, W^X, quotas and final-owner cleanup. Compare classic Wasm as well as WasmGC; verify install failure rollback and parked-code lifetime. |
| 2 | Reuse root-scope storage owned by each native execution/fiber. | Preserve the existing root contents and copy semantics first. Verify trap restoration, tail calls, host reentry, suspension/resume/cancel and nested exception rollback. |
| 3 | Introduce an allocation budget informed by post-GC live bytes, and reduce tracing cost. | Measure collection time/frequency, retained bytes, RSS and identity-table traversal. Preserve Store identities, object/byte quotas and complete native/logical root closure. |
| 4 | Share a typed physical layout descriptor across allocation, tracing and generated access. | Initially retain 64-bit reference encoding where required. Cover interpreter/JIT agreement, packed signed loads, V128, subtype prefixes, arrays, null/bounds checks and moving collections. Add inline allocation only after rooting and accounting are complete. |

The first two steps have direct diagnostic controls behind them: code packing
improved the classic-Wasm probe without materially changing executed instruction
count; root-buffer reuse improved the GC probe while preserving root contents.
These were temporary experiments, not production ownership designs. A process-
global arena or freelist is not the proposed repair.

Collection policy and tracing must be considered together. The earlier small
fixed-threshold GC experiment reduced retention but substantially slowed the
probe. Adding frequent full collections on top of expensive root/value/identity
traversal is therefore not an acceptable performance conclusion. Likewise,
changing physical field layout need not change every public `Value` or FFI
`GcSlot` representation at once.

The longer-term stack-map route is plausible because Wasmoon already records
live-reference information. It is a larger lifetime change than reusing storage:
active and parked execution, bound inputs, native exception graphs and host
handles must all remain traceable. Arena-owned payloads are edges, not independent
roots. This invariant cannot be traded for a faster active-stack-only scanner.

Neither adopting V8's full generational collector nor switching Wasmtime
collectors is a prerequisite for these steps. Their barriers, handles, heap
movement and ownership rules differ from Wasmoon's Store transactions. Each step
needs an isolated benchmark and correctness control before choosing the next.
