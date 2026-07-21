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

## Allocation strategies

`Backtracking` is the default production strategy. It allocates fragmented
live ranges, uses fixed-register, soft-register, and cross-fragment hints, evicts cheaper
fragments, and reuses compatible non-overlapping spill slots.

`SinglePass` is an explicit low-compile-latency strategy. It uses the same
fragmented plan and verification contract but does not evict an existing
fragment to make room for a more valuable one, so it may spill earlier.
Callers should select it only when compile latency matters more than generated
code quality.

```moonbit check
///|
test "select the low-latency allocator explicitly" {
  let config = RegallocConfig::RegallocConfig(strategy=SinglePass)
  inspect(config.strategy(), content="SinglePass")
}
```

## Integrating a machine IR

Implement `FunctionView` over the machine IR and provide a `MachineEnv` with
allocatable and scratch registers. Block arguments passed to CFG methods are
dense layout indices; `block_id_at` maps them back to the machine IR's stable
block id for edge edits.

The view also distinguishes function entry values from block parameters and
defines spill size, alignment, and slot-sharing compatibility. Operand timing
uses `Early` and `Late` points, allowing an early input and late output to
share a register safely across one instruction.

Call `allocate_function(view, environment, config?)`. With verification
enabled (the default), the allocator symbolically checks operand values,
clobbers, instruction edits, CFG joins, and block-argument transfers before
returning the plan.

`Milky2018/machv_regalloc` is the reference adapter. AArch64 and x64 both use
this path before target emission.

## Production integration

Wasmoon's AArch64 and x64 JIT pipelines lower semantic MachV to target-owned
VCode, expose that VCode directly through `FunctionView`, and explicitly select
`Backtracking`. The adapter materializes the returned plan into Target VCode's
separate `Allocation` side tables. The aggregate target pipeline verifies
selected VCode before allocation and independently verifies the materialized
VCode allocation afterward, without repeating the generic plan verifier's
whole-function analysis. Production compilation does not fall back to
`SinglePass`.

The cutover is functionally complete, but compile-time, runtime, and emitted
code-size acceptance remain open. See the current
[register-allocation cutover status](../../docs/perf/machv-migration/regalloc-cutover-status.md)
for measurements and limitations.

## Expert packages

- `Milky2018/regalloc/planning` provides standalone planning utilities.
- `Milky2018/regalloc/backtracking` provides lower-level policy components for
  specialized allocator integrations. It is not a second production allocator;
  the root `allocate_function` entry point owns strategy selection, plan
  construction, and verification.
