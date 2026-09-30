# Wasmtime context layout review

Source review dated 2026-09-30, informing ISS-602. No runtime changes or
performance measurements are included in this review.

## Baselines

- Latest published release checked through GitHub: [v49.0.1](https://github.com/bytecodealliance/wasmtime/releases/tag/v49.0.1),
  commit `46c23a87dac1465986a8ad53ba6a7ae49372857b`.
- Upstream main: `c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef`.
- Wasmoon migration branch: `b141554a74d16ac62aac16f4e74a4e51ccdc82e6`.

The upstream `vmctxtypes.rs`, `instance.rs`, `vmcontext.rs`, `traphandlers.rs`
and `fiber.rs` files are unchanged between these upstream revisions. Main adds
GC-header layout centralization and continuation GC payload/ASan metadata;
those additions are not prerequisites for module-shaped instance allocation.

## One layout definition, several consumers

`for_each_vmctx_type!` defines both core and component context layouts. Core
VMContext consists of a fixed prefix followed by arrays and optional fields
whose sizes depend on the module. Explicit alignment is part of the definition.
The definition includes access properties such as `readonly`, `can_move`, and
pointee regions; these are consumed by compiler alias-region/accessor generation
as well as offset computation. This is more than sharing numeric constants.

Sources: [layout schema](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/environ/src/vmctxtypes.rs#L1-L247),
[compiler consumers](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/cranelift/src/alias_region.rs#L1-L19).

`VMOffsets::new(pointer_size, module)` computes offsets from imported/defined
entity counts, owned memories, escaped functions, runtime data and startup
requirements. Compilation uses target pointer size; runtime construction uses
`HostPtr`. Offsets are available during compilation, so dynamic layout does not
require dynamic offset lookup in generated code. `region_sizes()` explains the
space consumed by each region.

Sources: [descriptor and construction](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/environ/src/vmoffsets.rs#L453-L508),
[counts and accounting](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/environ/src/vmoffsets.rs#L665-L790),
[compiler construction](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/cranelift/src/func_environ.rs#L293),
[runtime construction](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/module.rs#L557).

## What 48 bytes means

On a 64-bit target, the fixed prefix is:

| Offset | Field |
| --- | --- |
| 0 | 4-byte magic, followed by 4-byte padding |
| 8 | Store context pointer |
| 16 | Builtin functions pointer |
| 24 | Epoch counter pointer |
| 32 | GC heap data pointer |
| 40 | Type IDs pointer |

These slots exist even when an individual module does not use every feature.
Following them are imported memories, defined-memory pointers, owned memory
definitions, imported functions/tables/globals/tags, defined tables/globals/tags,
escaped function references, an optional startup reference, and runtime data.
Memory regions appear first to keep frequently used instruction displacements
small. There is no universal full function-reference record for every function:
the reference array is sized by escaped functions.

Source: [fixed and dynamic fields](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/environ/src/vmctxtypes.rs#L121-L247).

Illustrative VMContext sizes derived from this schema, with 8-byte pointers and
all unmentioned counts/flags zero:

| Module shape | Derived VMContext bytes |
| --- | ---: |
| Empty | 48 |
| One defined, non-shared memory | 80 |
| Two defined, non-shared memories | 96 |
| One defined table | 64 |
| One defined global | 64 |

The single-memory case is 48 + 8 for its definition pointer + 16 for its inline
definition + 8 alignment padding. These are schema calculations, not measured
allocator usage. Exported functions, initialization data and other entities can
increase an actual module's size.

The allocation also includes the runtime `Instance`: its layout is computed as
`size_of::<Instance>() + offsets.size_of_vmctx()`. Memory/table owners, passive
elements, module information and Store association live outside the generated
code's prefix. The owning handle preserves a stable address and derives VMContext
from the original allocation; pointer provenance and alignment are explicit
correctness constraints. Therefore 48 bytes cannot be compared to Wasmoon's
complete 352-byte owner as a total-memory comparison.

Sources: [Instance fields](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/vm/instance.rs#L90-L151),
[allocation size](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/vm/instance.rs#L821-L827),
[pointer provenance](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/vm/instance.rs#L1574-L1629).

## Memory access is specialized by ownership

For a defined non-shared memory, generated code directly loads the inline
`VMMemoryDefinition` fields at compiled VMContext offsets. The pointer array also
exists for runtime use, but that does not force generated code to traverse it.
Imported and shared memories use a pointer to the authoritative definition.
Base loads become readonly only when the memory configuration guarantees a
stable base. Length is mutable; shared length uses atomic storage.

Memory growth updates the inline definition for non-shared memory. A compact
layout must preserve this synchronization and the identities seen by importers.
Moving every hot field behind a separately allocated optional object would lose
an important property of this design.

Sources: [three compiler access paths](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/cranelift/src/func_environ.rs#L1671-L1766),
[definition](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/environ/src/vmtypes.rs#L60-L77),
[growth update](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/vm/instance.rs#L774-L795).

## Execution state has a different lifetime

`VMStoreContext` belongs to the Store and exposes currently active execution
metadata. `EntryStoreContext` saves/restores entry/exit, trap and stack state;
stack-resident `CallThreadState` records form a TLS activation chain. This is
not one unprotected mutable record standing in for all suspended invocations.

Suspension detaches the fiber's activation chain, saves its current metadata and
restores the previous Store projection. Resume reverses this. Stack limits,
guard ranges and executor/future state also have restoration guards. Dropping
an unfinished fiber future explicitly resumes it with a cancellation error so
cleanup can complete before its stack is deallocated. RC ownership alone does
not perform these execution-state transitions.

Sources: [Store context](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/environ/src/vmtypes.rs#L300-L486),
[entry save/restore](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/func.rs#L1490-L1642),
[activation suspension](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/vm/traphandlers.rs#L1092-L1409),
[fiber disposal](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/fiber.rs#L455-L503).

## Application to Wasmoon

At the reviewed Wasmoon revision, `vmcontext_abi.mbt` obtains one process-wide
fixed layout from C. `native_wasm_lower.mbt` converts it to field paths. The
runtime allocates a fixed ABI structure plus fixed private state. Previous
activation and MoonBit RC migrations improve ownership but do not change that
layout model.

Sources: [current layout](https://github.com/Milky2018/wasmoon/blob/b141554a74d16ac62aac16f4e74a4e51ccdc82e6/modules/wasmoon_jit/vmcontext_abi.mbt),
[compiler adapter](https://github.com/Milky2018/wasmoon/blob/b141554a74d16ac62aac16f4e74a4e51ccdc82e6/modules/wasmoon_jit/native_wasm_lower.mbt),
[native ownership](https://github.com/Milky2018/wasmoon/blob/b141554a74d16ac62aac16f4e74a4e51ccdc82e6/modules/wasmoon_jit/jit_ffi/jit_context.h).

Recommended sequence (design conclusions, not implemented changes):

1. Introduce an immutable module-shaped layout in Wasmoon-owned MoonBit code.
   Compute checked offsets, sizes and alignment from module requirements;
   supply that descriptor to allocation and the compiler adapter. Keep generic
   compiler packages product-neutral and reuse their symbolic field paths.
2. Keep MoonBit RC owners for retained arrays and objects. Use a narrow native
   allocation/access boundary for stable ABI storage. C helpers consume the
   descriptor instead of independently rediscovering module shape. Preserve
   activation ownership while migrating instance fields.
3. Retain direct hot loads for suitable instance-owned fields, and indirect
   access for shared/imported definitions. Wasmoon's existing memory/global
   ownership permits different sharing patterns; prove address and growth
   coherence before copying upstream's inline representation.
4. Update artifact codegen revision and validate descriptor compatibility.
   Wasmtime normally checks version and engine metadata on deserialize; it is
   not evidence for a stable context ABI across releases. Explicitly support
   the existing standalone/legacy context contract during migration.
5. Validate layout/allocation agreement and generated accesses together.
   Cover empty, single/multi-memory, shared/imported memory, table growth,
   globals, GC, exceptions, nested calls, suspension, cancellation and old
   artifacts. Account separately for ABI bytes, private owners, retained arrays,
   shared storage and activation costs; benchmark isolated binaries and include
   address-placement controls before claiming performance improvements.

Upstream validation references: [generated layout tests](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/runtime/vm/vmcontext.rs#L200-L297),
[artifact compatibility](https://github.com/bytecodealliance/wasmtime/blob/c21f5ede5d37e4e826f9e4343a1fa6e48f8ea6ef/crates/wasmtime/src/engine/serialization.rs#L100-L131).

The target is module-proportional storage with explicit lifetimes and efficient
access, not a predetermined 48-byte total or a new general-purpose macro DSL.
