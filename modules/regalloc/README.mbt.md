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

## Allocation strategies

`Backtracking` is the default production strategy. It allocates fragmented
live ranges, uses fixed-register and cross-fragment hints, evicts cheaper
fragments, and reuses compatible non-overlapping spill slots.

`SinglePass` is an explicit low-compile-latency strategy. It assigns one home
per value and may spill earlier, so callers should select it only when compile
latency matters more than generated-code quality.

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

## Expert packages

- `Milky2018/regalloc/planning` provides standalone planning utilities.
- `Milky2018/regalloc/backtracking` provides lower-level policy components for
  specialized allocator integrations.
