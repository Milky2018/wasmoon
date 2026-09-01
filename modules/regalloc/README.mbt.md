# regalloc

`regalloc` is a target-independent register allocator for machine IRs. It
reads a function through a narrow, read-only `FunctionView` and returns an
`AllocationPlan`; it does not copy the client's instruction or CFG objects.

The plan contains:

- a stable home for every value;
- a location for every instruction operand;
- before/after edits for reloads, spills, fixed registers, and tied operands;
- edge edits for block arguments;
- reusable spill-slot layouts.

Operand constraints and placement preferences are separate contracts. A fixed
register is a hard correctness requirement and may require an insertion edit.
A physical-register preference only orders otherwise legal allocation choices;
it is ignored rather than causing an extra spill, split, move, or failure when
the preferred register cannot hold the live range.

## Allocation

The allocator builds allocation bundles from compatible SSA edge affinities,
allocates each bundle atomically, splits
bundles when pressure requires it, evicts cheaper residents, and reuses
compatible non-overlapping spill slots. Fixed-register, soft-register, and
cross-fragment hints all feed this implementation. There is no alternate
allocation strategy; compile-time work belongs in the same verified allocator
rather than a lower-quality fallback.

## Integrating a machine IR

Implement `FunctionView` over the machine IR and provide a `MachineEnv` with
allocatable and scratch registers. Block arguments passed to CFG methods are
dense layout indices; `block_id_at` maps them back to the machine IR's stable
block id for edge edits. Collection queries return non-owning, read-only
`ArrayView` spans. Implementations must keep their backing storage alive for
the allocation call and should not allocate a collection per query.

Scratch registers have two distinct roles. `scratch_regs` are always available
to resolve allocator edits such as spill reloads and parallel moves. By default
they may also hold instruction operands when all allocatable registers are
occupied. A target whose emitter reserves those registers for instruction-local
expansion must call `with_operand_scratch_regs([])` (or provide the safe subset),
while leaving the edit scratch set intact.

`fixed_operand_regs` are a third, narrower role. They are excluded from value
homes and allocator-chosen scratches, but an instruction may name one explicitly
with `FixedReg`; operand materialization can then move the value into that named
register at the instruction boundary. This models reserved ISA operands such as
an x64 instruction-local temporary without granting the allocator general
scratch authority over that register.

The view also distinguishes function entry values from block parameters and
defines spill size, alignment, and slot-sharing compatibility. Operand timing
uses `Early` and `Late` points, allowing an early input and late output to
share a register safely across one instruction.

Call `allocate_function(view, environment, config?)`. With verification
enabled (the default), the allocator symbolically checks operand values,
clobbers, instruction edits, CFG joins, and block-argument transfers before
returning the plan.

`Milky2018/vcode_regalloc` is the reference adapter. AArch64 and x64 both use
this path before target emission.

## Production integration

Wasmoon's AArch64 and x64 JIT pipelines lower MilkIR directly to target-owned
VCode and expose that VCode directly through `FunctionView`. The adapter
materializes the returned plan into Target VCode's separate `Allocation` side
tables. The aggregate target pipeline verifies
selected VCode before allocation and independently verifies the materialized
VCode allocation afterward, without repeating the generic plan verifier's
whole-function analysis.

The production integration is complete. CI validates allocation correctness on
both native targets; retired allocators and backends are not rebuilt as
performance or code-size acceptance baselines.
