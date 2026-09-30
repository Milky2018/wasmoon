# Wasmtime instance state: ownership beyond the VMContext prefix

Source review dated 2026-09-30. This follows
[the context layout review](wasmtime-context-layout-review.md), using the same
upstream main revision, `c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef`, verified in
the local upstream checkout. It does not claim that revision remains upstream
HEAD. All upstream links below are pinned to that revision. This is source
inspection, without allocation measurements or performance experiments.

## The comparison boundary

The 48-byte figure describes the fixed core VMContext prefix on a 64-bit
target. Module-dependent arrays follow it. The allocation also contains the
runtime `Instance` before that context. `Instance` retains runtime module
information, memory/table owners, passive element segments, an optional
`wmemcheck` owner, and its Store association. Its allocation size is computed
from `size_of::<Instance>() + offsets.size_of_vmctx()`. Neither 48 bytes nor
that allocation alone includes every retained allocation or shared owner.

Sources: [context schema](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/environ/src/vmctxtypes.rs#L121-L247),
[Instance fields](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/vm/instance.rs#L90-L151),
[allocation formula](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/vm/instance.rs#L821-L827).

## Where the state lives

| State | Ownership at the pinned revision |
| --- | --- |
| Canonical types and GC layouts | Engine type registry; module code retains registered type collections. |
| Module type ID mapping and tracing metadata | `EngineCode.signatures: TypeCollection`; VMContext contains a pointer to its type IDs. |
| GC heap and reference tables | Optional `StoreOpaque.gc_store`, including heap, externref host data, function-reference table and feature-gated continuation-reference table. |
| GC roots and pending exception | `StoreOpaque.gc_data: StoreGcData`; exception payloads are GC heap objects. |
| Compiled function index and stack maps | Code/module metadata reached through the Store's module registry. |
| Escaped Wasm function references | Module-sized VMContext array. Other pinned function references and host function owners also live in Store `FuncRefs`. |
| Hostcall closure | Separate `VMArrayCallHostFuncContext.host_state`, retained through a `HostFunc` owner. |
| Fuel, epoch deadline and active execution projection | Store `VMStoreContext`; entry guards and activation/fiber state preserve nesting and suspension. |
| Continuation stack objects | Feature-gated `StoreOpaque.continuations: Vec<Box<VMContRef>>`. |
| Passive data drop state | Per-instance VMContext runtime-data length slots. |
| Passive element contents/drop state | `Instance.passive_elements`, cleared through the GC-aware segment implementation. |

### Types and GC

The Engine owns a `TypeRegistry`; its inner state includes `type_to_gc_layout`.
`EngineCode` owns a `TypeCollection` containing registered recursion groups,
module-to-engine type IDs and tracing information. Initializing an instance
writes a pointer from `runtime_info.type_ids()` into the VMContext. This is a
reference to retained type metadata, not a copy of all type descriptions into
the prefix.

Sources: [Engine ownership](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/engine.rs#L69-L82),
[GC layout registry](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/type_registry.rs#L634-L685),
[type collection](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/type_registry.rs#L90-L97),
[code owner](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/code.rs#L99-L118),
[type pointer initialization](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/vm/instance.rs#L1186-L1189).

Store GC ownership is separate: `GcStore` owns the heap and reference tables;
`StoreGcData` owns roots, host-allocation type registrations, the pending
exception root, and a subtype-check cache. It would therefore be inaccurate to
say that *all* type-related state is Engine-global, or that shrinking VMContext
eliminates Store GC storage.

Sources: [Store fields](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/store.rs#L463-L481),
[GC store](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/vm/gc.rs#L47-L84),
[GC roots and caches](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/store/gc.rs#L27-L68).

### Functions, safepoints and host closures

These are several distinct structures. Wasm tables have per-instance runtime
owners and ABI definitions. Escaped function references occupy a module-sized
VMContext region. The Store's `FuncRefs` arena additionally pins references,
patches missing trampolines and retains host-function definitions. The module
registry indexes code and holds an `Arc<CompiledFunctionsTable>`; GC stack
walking resolves a frame PC through this registry and reads the stack map from
code memory. Stack maps are not per-instance arrays in the fixed prefix.

Sources: [VMContext function references](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/environ/src/vmctxtypes.rs#L209-L247),
[Store reference arena and owners](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/store/func_refs.rs#L13-L79),
[code registry](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/module/registry.rs#L58-L104),
[stack map lookup](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/store/gc.rs#L755-L785).

For safepoint ownership specifically, `CodeMemory::stack_map_data()` returns
the encoded section as a slice of the code mapping. The lookup above consumes
that section after resolving the active frame's code owner. This supports
sharing immutable prepared metadata with an artifact/code owner, provided that
owner remains alive for every live or suspended frame. It is not evidence that
a per-function runtime allocation is necessary for a function with no stack
maps, nor that all Store-dependent GC type resolution can be shared with code.
Debugging can introduce a private Store copy of code, so even upstream's
sharing model has an explicit Store-level mapping boundary.

Sources: [encoded stack-map section](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/code_memory.rs#L328-L333),
[shared and private code](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/code.rs#L99-L118).

A host closure is stored as `HostFuncState<F>.func` inside the boxed host state
of a distinct `VMArrayCallHostFuncContext`. `HostFunc` owns that context. The
Store may retain a uniquely owned or shared host function through `FuncRefs`.
Store user data `T`, limiters and call hooks instead live in `StoreInner<T>`.
These separate lifetimes matter when sharing one host function across Stores.

Sources: [closure owner](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/func.rs#L2226-L2250),
[host context](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/vm/vmcontext/vm_host_func_context.rs#L19-L59),
[Store user state](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/store.rs#L237-L268).

### Invocation control, exceptions and continuations

`VMStoreContext` is shared by the instances in a Store. It includes fuel,
epoch deadline and active execution metadata. `EntryStoreContext` saves and
restores entry state; `CallThreadState` and the fiber suspension/resumption
protocol preserve activation-specific state. Moving these fields to a Store
does not remove the need for separate suspended activation state.

Sources: [Store context](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/environ/src/vmtypes.rs#L302-L486),
[entry guard](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/func.rs#L1490-L1642),
[activation transfer](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/vm/traphandlers.rs#L1092-L1409).

There is no equivalent single per-instance exception/continuation arena to
copy mechanically. Exception objects allocate through the Store GC heap,
with a pending exception retained as a Store GC root. Continuation stack
objects are boxed in a Store vector; the allocator explicitly documents that
individual continuations are not currently deallocated and remain until Store
destruction. The separate GC continuation-reference table should not be
confused with this vector of stack objects.

Sources: [exception allocation](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/vm/gc.rs#L393-L414),
[pending exception](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/store/gc.rs#L27-L46),
[continuation allocation](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/store.rs#L2135-L2159).

### Segment state

Passive data uses module-retained bytes with per-instance base and length
slots initialized in VMContext. `data.drop` lowers to a zero store in the
corresponding length slot. Passive elements instead have evaluated values in
`Instance.passive_elements`; `passive_elem_drop` clears the segment with access
to the optional GC store. A design that moves all segment state to immutable
module metadata would incorrectly share mutation between instances.

Sources: [data initialization](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/vm/instance.rs#L1355-L1372),
[data.drop lowering](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/cranelift/src/func_environ.rs#L4155-L4177),
[element drop](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/vm/instance.rs#L991-L1011).

## Practical lessons for Wasmoon

These are design inferences from the ownership above, not implemented changes:

1. Compare generated-code ABI storage, per-instance owners, shared module/code
   metadata, Store/session state, and suspended activations separately. Do not
   compare a full native owner directly with Wasmtime's fixed prefix.
2. Move immutable type/function/safepoint metadata only when the retained module
   or code owner can prove its lifetime. Keep mutable segment state and resource
   definitions instance-specific, respecting imported/shared ownership.
3. Treat host closures, GC heaps, exception roots and continuation stacks as
   ownership decisions. Removing a pointer from the context does not remove
   its allocation, rooting requirements or destruction protocol.
4. A Store-style shared execution context requires save/restore invariants for
   nested calls, suspension, resumption and cancellation. Reference counting
   alone cannot supply those transitions.
5. Establish actual allocation accounting before claiming memory savings, and
   measure generated accesses and execution before claiming speed changes.
   The pinned sources supply neither Wasmoon's target owner size nor a
   performance result.
